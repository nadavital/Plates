import Foundation
import OSLog
import StoreKit

@MainActor @Observable
final class BillingService {
    static let shared = BillingService()

    private enum DefaultsKey {
        static let syncState = "billing.syncState.v1"
        static let lastSyncedAt = "billing.lastSyncedAt.v1"
        static let availableProducts = "billing.availableProducts.v1"
        #if DEBUG
        static let debugPlanOverride = "billing.debugPlanOverride.v1"
        #endif
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let encoder = JSONEncoder()
    @ObservationIgnored
    private let decoder = JSONDecoder()
    @ObservationIgnored
    private var transactionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored
    private var storeProductsByID: [String: Product] = [:]

    private let monetizationService: MonetizationService
    private let accountService: AppAccountService
    private let backendClient: TraiBackendClient
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Trai", category: "BillingService")

    private(set) var syncState: BillingSyncState
    private(set) var lastSyncedAt: Date?
    private(set) var availableProducts: [SubscriptionProductDefinition]
    private(set) var isLoadingProducts = false
    private(set) var isRestoringPurchases = false
    private(set) var purchaseInFlightProductID: String?
    private(set) var lastStoreKitErrorMessage: String? {
        didSet {
            guard let lastStoreKitErrorMessage, lastStoreKitErrorMessage != oldValue else { return }
            logger.error("StoreKit issue: \(lastStoreKitErrorMessage, privacy: .public)")
        }
    }
    private(set) var lastStoreKitRefreshAt: Date?
    #if DEBUG
    private(set) var debugPlanOverride: SubscriptionPlan?
    #endif

    private init(
        defaults: UserDefaults = .standard,
        monetizationService: MonetizationService? = nil,
        accountService: AppAccountService? = nil,
        backendClient: TraiBackendClient? = nil
    ) {
        self.defaults = defaults
        self.monetizationService = monetizationService ?? .shared
        self.accountService = accountService ?? .shared
        self.backendClient = backendClient ?? .shared

        if let rawSyncState = defaults.string(forKey: DefaultsKey.syncState),
           let syncState = BillingSyncState(rawValue: rawSyncState) {
            self.syncState = syncState
        } else {
            self.syncState = .localOnly
        }

        self.lastSyncedAt = defaults.object(forKey: DefaultsKey.lastSyncedAt) as? Date

        if let data = defaults.data(forKey: DefaultsKey.availableProducts),
           let storedProducts = try? decoder.decode([SubscriptionProductDefinition].self, from: data),
           !storedProducts.isEmpty {
            self.availableProducts = Self.normalizedProducts(storedProducts)
        } else {
            self.availableProducts = Self.defaultProducts
        }

        #if DEBUG
        if let rawDebugPlanOverride = defaults.string(forKey: DefaultsKey.debugPlanOverride),
           let debugPlanOverride = SubscriptionPlan(rawValue: rawDebugPlanOverride) {
            self.debugPlanOverride = debugPlanOverride
        } else {
            self.debugPlanOverride = nil
        }
        #endif

        startTransactionObservationIfNeeded()
    }

    var productIdentifiers: [String] {
        availableProducts.map(\.id)
    }

    var recommendedProduct: SubscriptionProductDefinition? {
        availableProducts.first(where: \.isPrimaryOffer) ?? availableProducts.first
    }

    var syncStatusDescription: String {
        let base = syncState.displayName
        guard let lastSyncedAt else { return base }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(base) • updated \(formatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
    }

    var storeKitStatusDescription: String {
        if isLoadingProducts {
            return "Loading App Store products..."
        }
        if let purchaseInFlightProductID,
           let product = availableProducts.first(where: { $0.id == purchaseInFlightProductID }) {
            return "Purchasing \(product.displayName)..."
        }
        if isRestoringPurchases {
            return "Restoring purchases..."
        }
        if let lastStoreKitErrorMessage {
            return Self.storeKitStatusLabel(for: lastStoreKitErrorMessage)
        }
        if !storeProductsByID.isEmpty {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            if let lastStoreKitRefreshAt {
                return "Loaded \(storeProductsByID.count) App Store products • \(formatter.localizedString(for: lastStoreKitRefreshAt, relativeTo: Date()))"
            }
            return "Loaded \(storeProductsByID.count) App Store products"
        }
        return "StoreKit products not loaded yet"
    }

    var manageSubscriptionsURL: URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    var storeKitUpsellMessage: String? {
        if let lastStoreKitErrorMessage {
            return Self.storeKitUpsellLabel(for: lastStoreKitErrorMessage)
        }
        if storeProductsByID.isEmpty, !isLoadingProducts {
            return "Purchases are temporarily unavailable right now."
        }
        return nil
    }

    private var usesBackendEntitlementSourceOfTruth: Bool {
        AccountSessionService.shared.isAuthenticated && accountService.backendEnvironment != .localPlaceholder
    }

    func isStoreKitProductLoaded(for productID: String) -> Bool {
        storeProductsByID[productID] != nil
    }

    func isCurrentPaidPlan(_ plan: SubscriptionPlan) -> Bool {
        monetizationService.currentPlan == plan && monetizationService.currentStatus.isEntitledToPaidFeatures
    }

    func prepareForStoreKit() {
        syncState = .readyForStoreKit
        persistSyncState()

        Task { @MainActor in
            await refreshStoreKitProductsIfNeeded(force: true)
            await refreshEntitlementsFromStoreKit(forceOverrideLocal: true)
        }
    }

    func refreshLocalState() {
        if availableProducts.isEmpty {
            availableProducts = Self.defaultProducts
            persistProducts()
        }

        startTransactionObservationIfNeeded()

        let shouldOverrideLocalState = syncState == .localOnly
        Task { @MainActor in
            await refreshStoreKitProductsIfNeeded()
            if AccountSessionService.shared.isAuthenticated {
                await AccountSessionService.shared.refreshAccountFromBackend()
                await reconcileAuthenticatedStoreKitPurchasesIfNeeded()
            } else {
                await refreshEntitlementsFromStoreKit(forceOverrideLocal: shouldOverrideLocalState)
            }
        }
    }

    func refreshAccessStateForImmediateUse() async {
        if availableProducts.isEmpty {
            availableProducts = Self.defaultProducts
            persistProducts()
        }

        startTransactionObservationIfNeeded()
        await refreshStoreKitProductsIfNeeded()

        if AccountSessionService.shared.isAuthenticated {
            await AccountSessionService.shared.refreshAccountFromBackend()
            await reconcileAuthenticatedStoreKitPurchasesIfNeeded()
            return
        }

        let shouldOverrideLocalState = syncState == .localOnly
        await refreshEntitlementsFromStoreKit(forceOverrideLocal: shouldOverrideLocalState)
    }

    func refreshStoreKitProductsIfNeeded(force: Bool = false) async {
        guard force || storeProductsByID.isEmpty else { return }
        await loadStoreKitProducts()
    }

    func loadStoreKitProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        lastStoreKitErrorMessage = nil
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: productIdentifiers)
            storeProductsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            availableProducts = mergeProductsWithStoreKit(products)
            lastStoreKitRefreshAt = Date()
            if products.isEmpty {
                lastStoreKitErrorMessage = Self.missingProductsMessage(
                    requestedIDs: productIdentifiers,
                    bundleID: Bundle.main.bundleIdentifier
                )
            }
            persistProducts()
        } catch {
            lastStoreKitErrorMessage = "Failed to load App Store products: \(error.localizedDescription)"
        }
    }

    func purchase(productID: String) async {
        syncState = .readyForStoreKit
        persistSyncState()

        if storeProductsByID[productID] == nil {
            await loadStoreKitProducts()
        }

        guard let product = storeProductsByID[productID] else {
            lastStoreKitErrorMessage = "This subscription is not available from App Store Connect yet."
            return
        }

        purchaseInFlightProductID = productID
        lastStoreKitErrorMessage = nil
        defer { purchaseInFlightProductID = nil }

        do {
            let purchaseResult: Product.PurchaseResult
            if let token = UUID(uuidString: accountService.installationID) {
                purchaseResult = try await product.purchase(options: [.appAccountToken(token)])
            } else {
                purchaseResult = try await product.purchase()
            }

            switch purchaseResult {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                if !usesBackendEntitlementSourceOfTruth {
                    applyEntitlements(
                        from: [transaction],
                        sourceDescription: "storekit-purchase"
                    )
                }
                await syncStoreKitTransactionsToBackend(
                    [transaction],
                    signedTransactions: [verificationResult.jwsRepresentation],
                    reason: "purchase"
                )
                await transaction.finish()
            case .pending:
                lastStoreKitErrorMessage = "Purchase is pending approval."
            case .userCancelled:
                lastStoreKitErrorMessage = nil
            @unknown default:
                lastStoreKitErrorMessage = "StoreKit returned an unknown purchase state."
            }
        } catch {
            lastStoreKitErrorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard !isRestoringPurchases else { return }

        syncState = .readyForStoreKit
        persistSyncState()

        isRestoringPurchases = true
        lastStoreKitErrorMessage = nil
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            await refreshEntitlementsFromStoreKit(forceOverrideLocal: true)
        } catch {
            lastStoreKitErrorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshEntitlementsFromStoreKit(forceOverrideLocal: Bool = false) async {
        #if DEBUG
        guard forceOverrideLocal || syncState != .localOnly else { return }
        #else
        guard forceOverrideLocal || syncState != .localOnly else { return }
        #endif

        var verifiedTransactions: [Transaction] = []
        var unverifiedMessages: [String] = []
        var signedTransactions: [String] = []

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.revocationDate == nil else { continue }
                verifiedTransactions.append(transaction)
                signedTransactions.append(result.jwsRepresentation)
            case .unverified(_, let verificationError):
                unverifiedMessages.append(verificationError.localizedDescription)
            }
        }

        if !unverifiedMessages.isEmpty {
            lastStoreKitErrorMessage = "Some App Store entitlements could not be verified."
        }

        if !usesBackendEntitlementSourceOfTruth {
            applyEntitlements(
                from: verifiedTransactions,
                sourceDescription: "storekit-current-entitlements"
            )
        }
        await syncStoreKitTransactionsToBackend(
            verifiedTransactions,
            signedTransactions: signedTransactions,
            reason: "refresh-entitlements"
        )
    }

    func applyRemotePayload(_ payload: BillingSyncPayload) {
        accountService.applyRemoteAccountSnapshot(payload.accountSnapshot)
        applyResolvedMonetizationState(
            entitlementSnapshot: payload.entitlementSnapshot,
            quotaSnapshot: payload.quotaSnapshot,
            transportMode: payload.transportMode,
            now: payload.syncedAt
        )

        availableProducts = Self.normalizedProducts(payload.availableProducts)
        syncState = payload.syncState
        lastSyncedAt = payload.syncedAt
        lastStoreKitErrorMessage = nil

        persistProducts()
        persistSyncState()
    }

    func resetToLocalState(now: Date = Date()) {
        availableProducts = Self.defaultProducts
        syncState = .localOnly
        lastSyncedAt = nil
        lastStoreKitErrorMessage = nil
        lastStoreKitRefreshAt = nil
        storeProductsByID = [:]

        applyResolvedMonetizationState(
            entitlementSnapshot: Self.localFallbackEntitlement(now: now),
            quotaSnapshot: Self.localFallbackQuotaSnapshot(now: now),
            transportMode: .directGemini,
            now: now
        )

        persistProducts()
        persistSyncState()
    }

    func handleSignedOutAccountState() {
        if availableProducts.isEmpty {
            availableProducts = Self.defaultProducts
            persistProducts()
        }

        startTransactionObservationIfNeeded()

        let now = Date()
        syncState = .readyForStoreKit
        lastSyncedAt = nil
        lastStoreKitErrorMessage = nil

        applyResolvedMonetizationState(
            entitlementSnapshot: Self.localFallbackEntitlement(now: now),
            quotaSnapshot: Self.localFallbackQuotaSnapshot(now: now),
            transportMode: .directGemini,
            now: now
        )

        persistSyncState()

        Task { @MainActor in
            await refreshStoreKitProductsIfNeeded()
            await refreshEntitlementsFromStoreKit(forceOverrideLocal: true)
        }
    }

    func reconcileAuthenticatedStoreKitPurchasesIfNeeded() async {
        var verifiedTransactions: [Transaction] = []
        var signedTransactions: [String] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            verifiedTransactions.append(transaction)
            signedTransactions.append(result.jwsRepresentation)
        }

        if !usesBackendEntitlementSourceOfTruth, !verifiedTransactions.isEmpty {
            applyEntitlements(
                from: verifiedTransactions,
                sourceDescription: "storekit-post-auth-reconcile"
            )
        }
        await syncStoreKitTransactionsToBackend(
            verifiedTransactions,
            signedTransactions: signedTransactions,
            reason: "post-auth-reconcile"
        )
    }

    #if DEBUG
    func setDebugSyncState(_ syncState: BillingSyncState) {
        self.syncState = syncState
        persistSyncState()
    }

    func setDebugTransportMode(_ transportMode: AITransportMode) {
        applyResolvedMonetizationState(
            entitlementSnapshot: monetizationService.entitlementSnapshot,
            quotaSnapshot: monetizationService.quotaSnapshot,
            transportMode: transportMode
        )
    }

    func applyDebugEntitlement(
        plan: SubscriptionPlan,
        status: SubscriptionStatus = .active,
        transportMode: AITransportMode? = nil
    ) {
        debugPlanOverride = plan
        persistDebugPlanOverride()

        let now = Date()
        let payload = BillingSyncPayload(
            accountSnapshot: accountService.currentSnapshot,
            entitlementSnapshot: EntitlementSnapshot(
                plan: plan,
                status: status,
                sourceDescription: "debug-billing-service",
                renewalDate: nil,
                lastValidatedAt: now
            ),
            quotaSnapshot: nil,
            transportMode: transportMode ?? monetizationService.aiTransportMode,
            availableProducts: availableProducts,
            syncState: syncState,
            syncedAt: now
        )
        applyRemotePayload(payload)
    }
    #endif

    private func startTransactionObservationIfNeeded() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(update)
            }
        }
    }

    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        do {
            let transaction = try verifiedTransaction(from: update)
            if transaction.revocationDate != nil {
                await syncStoreKitTransactionsToBackend(
                    [transaction],
                    signedTransactions: [update.jwsRepresentation],
                    reason: "transaction-revocation"
                )
                await refreshEntitlementsFromStoreKit(forceOverrideLocal: true)
                await transaction.finish()
                return
            }
            if !usesBackendEntitlementSourceOfTruth {
                applyEntitlements(
                    from: [transaction],
                    sourceDescription: "storekit-transaction-update"
                )
            }
            await syncStoreKitTransactionsToBackend(
                [transaction],
                signedTransactions: [update.jwsRepresentation],
                reason: "transaction-update"
            )
            await transaction.finish()
        } catch {
            lastStoreKitErrorMessage = "Transaction verification failed: \(error.localizedDescription)"
        }
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            transaction
        case .unverified(_, let verificationError):
            throw verificationError
        }
    }

    private func applyEntitlements(
        from transactions: [Transaction],
        sourceDescription: String
    ) {
        let matchedProducts = transactions.compactMap { transaction in
            resolveProductDefinition(for: transaction.productID)
        }

        let highestPlan = matchedProducts
            .map(\.plan)
            .max(by: { Self.planRank(for: $0) < Self.planRank(for: $1) }) ?? .free

        let renewalDate = transactions.compactMap(\.expirationDate).max()
        let now = Date()

        applyResolvedMonetizationState(
            entitlementSnapshot: EntitlementSnapshot(
                plan: highestPlan,
                status: .active,
                sourceDescription: sourceDescription,
                renewalDate: renewalDate,
                lastValidatedAt: now
            ),
            quotaSnapshot: nil,
            transportMode: monetizationService.aiTransportMode,
            now: now
        )

        if !matchedProducts.isEmpty {
            var updatedAccount = accountService.currentSnapshot
            updatedAccount.identityMode = .appStoreAccount
            updatedAccount.lastSyncedAt = now
            accountService.applyRemoteAccountSnapshot(updatedAccount)
        }

        syncState = .readyForStoreKit
        lastSyncedAt = now
        persistSyncState()
    }

    private func syncStoreKitEntitlementsToBackend(reason: String) async {
        var verifiedTransactions: [Transaction] = []
        var signedTransactions: [String] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            verifiedTransactions.append(transaction)
            signedTransactions.append(result.jwsRepresentation)
        }

        await syncStoreKitTransactionsToBackend(
            verifiedTransactions,
            signedTransactions: signedTransactions,
            reason: reason
        )
    }

    private func applyResolvedMonetizationState(
        entitlementSnapshot: EntitlementSnapshot,
        quotaSnapshot: AIQuotaSnapshot? = nil,
        transportMode: AITransportMode? = nil,
        now: Date = Date()
    ) {
        monetizationService.applyRemoteState(
            entitlementSnapshot: resolvedEntitlementSnapshot(
                entitlementSnapshot,
                now: now
            ),
            quotaSnapshot: quotaSnapshot,
            transportMode: transportMode
        )
    }

    private func resolvedEntitlementSnapshot(
        _ entitlementSnapshot: EntitlementSnapshot,
        now: Date
    ) -> EntitlementSnapshot {
        #if DEBUG
        guard let debugPlanOverride else { return entitlementSnapshot }
        return EntitlementSnapshot(
            plan: debugPlanOverride,
            status: .active,
            sourceDescription: "debug-billing-service",
            renewalDate: nil,
            lastValidatedAt: now
        )
        #else
        return entitlementSnapshot
        #endif
    }

    #if DEBUG
    private func persistDebugPlanOverride() {
        if let debugPlanOverride {
            defaults.set(debugPlanOverride.rawValue, forKey: DefaultsKey.debugPlanOverride)
        } else {
            defaults.removeObject(forKey: DefaultsKey.debugPlanOverride)
        }
    }
    #endif

    private func syncStoreKitTransactionsToBackend(
        _ transactions: [Transaction],
        signedTransactions: [String]? = nil,
        reason: String
    ) async {
        guard let session = AccountSessionService.shared.sessionSnapshot else {
            return
        }

        let accountSnapshot = accountService.currentSnapshot
        guard accountSnapshot.backendEnvironment != .localPlaceholder else {
            return
        }

        let entitlementRecords = transactions.map { transaction in
            StoreKitEntitlementRecord(
                productID: transaction.productID,
                transactionID: transaction.id,
                originalTransactionID: transaction.originalID,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate,
                isUpgraded: transaction.isUpgraded
            )
        }

        let signedTransactionsToSync = signedTransactions ?? []

        do {
            let payload = try await backendClient.syncStoreKitEntitlements(
                signedTransactions: signedTransactionsToSync,
                entitlementRecords,
                session: session,
                accountSnapshot: accountSnapshot
            )
            applyRemotePayload(payload)
        } catch {
            lastStoreKitErrorMessage = "Failed to sync subscriptions to backend after \(reason): \(error.localizedDescription)"
        }
    }

    private func mergeProductsWithStoreKit(_ products: [Product]) -> [SubscriptionProductDefinition] {
        let storeKitProductsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return availableProducts.map { definition in
            guard let product = storeKitProductsByID[definition.id] else {
                return definition
            }

            return SubscriptionProductDefinition(
                id: definition.id,
                plan: definition.plan,
                displayName: product.displayName,
                priceDisplay: product.displayPrice,
                billingPeriodLabel: Self.billingPeriodLabel(for: product.subscription?.subscriptionPeriod) ?? definition.billingPeriodLabel,
                monthlyAIUnits: definition.monthlyAIUnits,
                isPrimaryOffer: definition.isPrimaryOffer,
                marketingPoints: definition.marketingPoints
            )
        }
    }

    private func persistSyncState() {
        defaults.set(syncState.rawValue, forKey: DefaultsKey.syncState)
        defaults.set(lastSyncedAt, forKey: DefaultsKey.lastSyncedAt)
    }

    private func persistProducts() {
        guard let data = try? encoder.encode(availableProducts) else { return }
        defaults.set(data, forKey: DefaultsKey.availableProducts)
    }

    private func resolveProductDefinition(for productID: String) -> SubscriptionProductDefinition? {
        availableProducts.first(where: { $0.id == productID })
    }

    private static func normalizedProducts(_ products: [SubscriptionProductDefinition]) -> [SubscriptionProductDefinition] {
        let normalizedProducts = products
            .filter { $0.id == "trai.pro.monthly" }
            .map {
                SubscriptionProductDefinition(
                    id: $0.id,
                    plan: .pro,
                    displayName: "Trai Pro",
                    priceDisplay: $0.priceDisplay,
                    billingPeriodLabel: $0.billingPeriodLabel,
                    monthlyAIUnits: SubscriptionPlan.pro.monthlyAIUnits,
                    isPrimaryOffer: true,
                    marketingPoints: $0.marketingPoints
                )
            }

        return normalizedProducts.isEmpty ? defaultProducts : normalizedProducts
    }

    private static func planRank(for plan: SubscriptionPlan) -> Int {
        switch plan {
        case .free:
            0
        case .pro:
            1
        case .developer:
            2
        }
    }

    private static func billingPeriodLabel(for period: Product.SubscriptionPeriod?) -> String? {
        guard let period else { return nil }

        let unitLabel: String
        switch period.unit {
        case .day:
            unitLabel = period.value == 1 ? "day" : "days"
        case .week:
            unitLabel = period.value == 1 ? "week" : "weeks"
        case .month:
            unitLabel = period.value == 1 ? "month" : "months"
        case .year:
            unitLabel = period.value == 1 ? "year" : "years"
        @unknown default:
            unitLabel = "period"
        }

        if period.value == 1 {
            return "per \(unitLabel)"
        }
        return "every \(period.value) \(unitLabel)"
    }

    private static func missingProductsMessage(
        requestedIDs: [String],
        bundleID: String?
    ) -> String {
        let ids = requestedIDs.joined(separator: ", ")
        let resolvedBundleID = bundleID ?? "unknown bundle"

        #if DEBUG
        return "No App Store products were returned for \(ids). In local testing, this usually means the subscription is not available in App Store Connect for \(resolvedBundleID), or the app is not running with a StoreKit test configuration."
        #else
        return "No App Store products were returned for \(ids). Verify the subscription is available in App Store Connect for \(resolvedBundleID)."
        #endif
    }

    private static func isMissingProductsMessage(_ message: String) -> Bool {
        message.hasPrefix("No App Store products were returned for ")
    }

    private static func storeKitStatusLabel(for message: String) -> String {
        if message == "Purchase is pending approval." {
            return "Purchase pending approval"
        }
        if message.hasPrefix("Restore failed:") {
            return "Restore unavailable right now"
        }
        if message.hasPrefix("Purchase failed:") {
            return "Purchase unavailable right now"
        }
        if isMissingProductsMessage(message) || message == "This subscription is not available from App Store Connect yet." {
            return "App Store products unavailable"
        }
        return "App Store unavailable right now"
    }

    private static func storeKitUpsellLabel(for message: String) -> String {
        if message == "Purchase is pending approval." {
            return "Your purchase is pending approval."
        }
        if message.hasPrefix("Restore failed:") {
            return "We couldn't restore purchases right now. Please try again."
        }
        if message.hasPrefix("Purchase failed:") {
            return "We couldn't complete the purchase right now. Please try again."
        }
        return "Purchases are temporarily unavailable right now."
    }

    private static func localFallbackEntitlement(now: Date) -> EntitlementSnapshot {
        #if DEBUG
        let defaultPlan: SubscriptionPlan = .developer
        #else
        let defaultPlan: SubscriptionPlan = .free
        #endif

        return EntitlementSnapshot(
            plan: defaultPlan,
            status: .active,
            sourceDescription: "local-fallback",
            renewalDate: nil,
            lastValidatedAt: now
        )
    }

    private static func localFallbackQuotaSnapshot(now: Date, calendar: Calendar = .current) -> AIQuotaSnapshot {
        let periodStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? now
        return AIQuotaSnapshot(
            periodStart: periodStart,
            periodEnd: periodEnd,
            usedUnits: 0,
            bonusUnits: 0,
            featureUsageCounts: [:],
            lastUpdatedAt: now
        )
    }

    private static let defaultProducts: [SubscriptionProductDefinition] = [
        SubscriptionProductDefinition(
            id: "trai.pro.monthly",
            plan: .pro,
            displayName: "Trai Pro",
            priceDisplay: "$3.99",
            billingPeriodLabel: "per month",
            monthlyAIUnits: SubscriptionPlan.pro.monthlyAIUnits,
            isPrimaryOffer: true,
            marketingPoints: [
                "Coach chat",
                "Food photo analysis",
                "Personalized nutrition and workout plans"
            ]
        )
    ]
}
