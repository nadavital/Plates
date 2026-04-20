import SwiftUI
import AuthenticationServices
import SwiftData

struct DeveloperSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @State private var presentedAccountSetupContext: AccountSetupContext?

    private var hasCurrentPaidSubscription: Bool {
        guard let billingService else { return false }
        return billingService.availableProducts.contains { billingService.isCurrentPaidPlan($0.plan) }
    }

    private var hasLoadedProducts: Bool {
        guard let billingService else { return false }
        return !billingService.availableProducts.isEmpty
    }

    var body: some View {
        List {
            if appAccountService != nil || accountSessionService != nil || billingService != nil || monetizationService != nil {
                DeveloperOverviewSection(
                    accountSessionService: accountSessionService,
                    appAccountService: appAccountService,
                    billingService: billingService,
                    monetizationService: monetizationService
                )
            }

            if let accountSessionService, let appAccountService {
                DeveloperAccountSection(
                    colorScheme: colorScheme,
                    accountSessionService: accountSessionService,
                    appAccountService: appAccountService,
                    onRefreshAccountState: refreshAccountState,
                    onSignOut: accountSessionService.signOut,
                    onAppleSignIn: handleAppleSignIn,
                    backendActionTitle: backendActionTitle(for: appAccountService),
                    onSwitchBackend: { switchToRecommendedBackend(using: appAccountService) }
                )
            }

            if let billingService {
                DeveloperStoreKitSection(
                    billingService: billingService,
                    hasCurrentPaidSubscription: hasCurrentPaidSubscription,
                    hasLoadedProducts: hasLoadedProducts,
                    onLoadProducts: loadStoreKitProducts,
                    onRestorePurchases: restorePurchases,
                    onSubscribe: subscribe
                )
            }

            debugSection
        }
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
    }

    @ViewBuilder
    private var debugSection: some View {
#if DEBUG
        if let monetizationService, let billingService, let appAccountService {
            DeveloperOverridesSection(
                billingService: billingService,
                monetizationService: monetizationService,
                appAccountService: appAccountService,
                debugPlanBinding: debugPlanBinding(for: billingService, monetizationService: monetizationService),
                debugPlanPreviewBinding: debugPlanPreviewBinding(for: billingService),
                debugSyncStateBinding: debugSyncStateBinding(for: billingService),
                debugIdentityBinding: debugIdentityBinding(for: appAccountService),
                debugBackendBinding: debugBackendBinding(for: appAccountService),
                debugAIProviderOverrideBinding: debugAIProviderOverrideBinding(for: appAccountService)
            )
        }

        DeveloperFoodMemorySection()
#endif
    }

    private func refreshAccountState() {
        guard let accountSessionService else { return }
        Task {
            await accountSessionService.refreshAccountFromBackend()
        }
    }

    private func loadStoreKitProducts() {
        guard let billingService else { return }
        Task {
            await billingService.loadStoreKitProducts()
        }
    }

    private func restorePurchases() {
        guard accountSessionService?.isAuthenticated == true else {
            presentedAccountSetupContext = .restorePurchases
            return
        }
        guard let billingService else { return }
        Task {
            await billingService.restorePurchases()
        }
    }

    private func subscribe(to productID: String) {
        guard accountSessionService?.isAuthenticated == true else {
            presentedAccountSetupContext = .billing
            return
        }
        guard let billingService else { return }
        Task {
            await billingService.purchase(productID: productID)
        }
    }

    private func handleAppleSignIn(
        _ result: Result<ASAuthorization, any Error>,
        using accountSessionService: AccountSessionService
    ) {
        switch result {
        case .success(let authorization):
            Task {
                await accountSessionService.handleAppleAuthorization(authorization)
            }
        case .failure(let error):
            accountSessionService.handleAuthorizationFailure(error)
        }
    }

    private func backendActionTitle(for appAccountService: AppAccountService) -> String? {
        guard let recommendedEnvironment = appAccountService.recommendedBackendEnvironmentForRealAccountSignIn else {
            return nil
        }
        return "Use \(recommendedEnvironment.displayName)"
    }

    private func switchToRecommendedBackend(using appAccountService: AppAccountService) {
        guard let recommendedEnvironment = appAccountService.recommendedBackendEnvironmentForRealAccountSignIn else {
            return
        }
        appAccountService.setBackendEnvironment(recommendedEnvironment)
    }

#if DEBUG
    private func debugPlanBinding(
        for billingService: BillingService,
        monetizationService: MonetizationService
    ) -> Binding<SubscriptionPlan> {
        Binding(
            get: { monetizationService.currentPlan },
            set: { billingService.applyDebugEntitlement(plan: $0) }
        )
    }

    private func debugPlanPreviewBinding(for billingService: BillingService) -> Binding<Bool> {
        Binding(
            get: { billingService.isDebugPlanPreviewEnabled },
            set: { billingService.setDebugPlanPreviewEnabled($0) }
        )
    }

    private func debugSyncStateBinding(for billingService: BillingService) -> Binding<BillingSyncState> {
        Binding(
            get: { billingService.syncState },
            set: { billingService.setDebugSyncState($0) }
        )
    }

    private func debugIdentityBinding(for appAccountService: AppAccountService) -> Binding<AppAccountIdentityMode> {
        Binding(
            get: { appAccountService.identityMode },
            set: { appAccountService.setDebugIdentityMode($0) }
        )
    }

    private func debugBackendBinding(for appAccountService: AppAccountService) -> Binding<BackendEnvironment> {
        Binding(
            get: { appAccountService.backendEnvironment },
            set: { appAccountService.setDebugBackendEnvironment($0) }
        )
    }

    private func debugAIProviderOverrideBinding(for appAccountService: AppAccountService) -> Binding<AIProviderOverride> {
        Binding(
            get: { appAccountService.debugAIProviderOverride },
            set: { appAccountService.setDebugAIProviderOverride($0) }
        )
    }
#endif
}

private struct DeveloperOverviewSection: View {
    let accountSessionService: AccountSessionService?
    let appAccountService: AppAccountService?
    let billingService: BillingService?
    let monetizationService: MonetizationService?

    @State private var showsStatusDetails = false

    var body: some View {
        Section {
            if let accountSessionService {
                DeveloperSummaryRow(
                    title: "Session",
                    value: accountSessionService.isAuthenticated ? "Signed In" : "Signed Out",
                    detail: accountSessionService.sessionStatusText
                )
            }

            if let monetizationService {
                DeveloperSummaryRow(
                    title: "Plan",
                    value: monetizationService.currentPlanDisplayText,
                    detail: monetizationService.quotaSummaryText
                )
            }

            if let appAccountService {
                DeveloperSummaryRow(
                    title: "Backend",
                    value: appAccountService.backendEnvironment.displayName,
                    detail: appAccountService.backendStatusText
                )
            }

#if DEBUG
            if let billingService, billingService.isDebugPlanPreviewEnabled {
                Label(
                    "Local plan preview: \(billingService.debugPlanOverride?.displayName ?? "On")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
#endif

            DisclosureGroup("Status Details", isExpanded: $showsStatusDetails) {
                if let accountSessionService {
                    LabeledContent("User", value: accountSessionService.currentUserDisplayName)

                    if let lastErrorMessage = accountSessionService.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let appAccountService {
                    LabeledContent("Account", value: appAccountService.shortAccountLabel)
                    LabeledContent("Identity", value: appAccountService.identityMode.displayName)
                }

                if let billingService {
                    LabeledContent("Billing Sync", value: billingService.syncStatusDescription)
                    LabeledContent("App Store", value: billingService.storeKitStatusDescription)
                }
            }
        } header: {
            Text("Overview")
        } footer: {
            Text("A compact view of the current backend, account, and billing state.")
        }
    }
}

private struct DeveloperAccountSection: View {
    let colorScheme: ColorScheme
    let accountSessionService: AccountSessionService
    let appAccountService: AppAccountService
    let onRefreshAccountState: () -> Void
    let onSignOut: () -> Void
    let onAppleSignIn: (Result<ASAuthorization, any Error>, AccountSessionService) -> Void
    let backendActionTitle: String?
    let onSwitchBackend: () -> Void

    var body: some View {
        Section {
            if appAccountService.backendEnvironment == .localDevelopment {
                TextField(
                    "http://192.168.1.23:8789",
                    text: Binding(
                        get: { appAccountService.customBackendBaseURL },
                        set: { appAccountService.setCustomBackendBaseURL($0) }
                    )
                )
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)

                if !appAccountService.customBackendBaseURL.isEmpty {
                    Button("Clear Custom Backend URL", role: .destructive) {
                        appAccountService.setCustomBackendBaseURL("")
                    }
                }
            }

            if accountSessionService.isAuthenticated {
                Button(action: onRefreshAccountState) {
                    Text(accountSessionService.isSyncingAccount ? "Syncing Account..." : "Refresh Account State")
                }
                .disabled(accountSessionService.isSyncingAccount)

                Button("Sign Out", role: .destructive, action: onSignOut)
            } else if let blockedReason = appAccountService.realAccountSignInBlockedReason {
                BackendRequirementCard(
                    message: blockedReason,
                    actionTitle: backendActionTitle,
                    action: onSwitchBackend
                )
            } else {
                SignInWithAppleButton(.signIn, onRequest: accountSessionService.configureAppleSignInRequest) { result in
                    onAppleSignIn(result, accountSessionService)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
            }
        } header: {
            Text("Account")
        } footer: {
            if appAccountService.backendEnvironment == .localDevelopment {
                Text("For on-device testing, enter a reachable backend URL like your Mac's LAN IP or a tunnel.")
            } else {
                Text("Use this area to test sign-in, sign-out, and account refresh behavior.")
            }
        }
    }
}

private struct DeveloperStoreKitSection: View {
    let billingService: BillingService
    let hasCurrentPaidSubscription: Bool
    let hasLoadedProducts: Bool
    let onLoadProducts: () -> Void
    let onRestorePurchases: () -> Void
    let onSubscribe: (String) -> Void

    var body: some View {
        Section {
            if hasLoadedProducts {
                ForEach(billingService.availableProducts) { product in
                    SubscriptionProductRow(
                        product: product,
                        isCurrentPlan: billingService.isCurrentPaidPlan(product.plan),
                        isLoadingPurchase: billingService.purchaseInFlightProductID == product.id,
                        canSubscribe: billingService.isStoreKitProductLoaded(for: product.id)
                            && billingService.purchaseInFlightProductID == nil
                            && !billingService.isRestoringPurchases
                            && !billingService.isCurrentPaidPlan(product.plan),
                        onSubscribe: {
                            onSubscribe(product.id)
                        }
                    )
                }
            }

            Button(action: onLoadProducts) {
                Text(billingService.isLoadingProducts ? "Loading Products..." : "Load App Store Products")
            }
            .disabled(billingService.isLoadingProducts || billingService.purchaseInFlightProductID != nil)

            Button(action: onRestorePurchases) {
                Text(billingService.isRestoringPurchases ? "Restoring..." : "Restore Purchases")
            }
            .disabled(billingService.isRestoringPurchases || billingService.purchaseInFlightProductID != nil)

            if hasCurrentPaidSubscription, let manageSubscriptionsURL = billingService.manageSubscriptionsURL {
                Link("Manage Subscription", destination: manageSubscriptionsURL)
            }
        } header: {
            Text("StoreKit Testing")
        } footer: {
            if hasLoadedProducts {
                Text("Use this section to load products, test purchases, and restore flows.")
            } else {
                Text("Load products first to inspect the configured StoreKit offers.")
            }
        }
    }
}

#if DEBUG
private struct DeveloperFoodMemorySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \FoodMemory.updatedAt, order: .reverse) private var foodMemories: [FoodMemory]

    @State private var isRunningResolver = false
    @State private var isRunningBackfill = false
    @State private var shadowSummary: FoodMemoryShadowSummary?
    @State private var suggestionDebugSummary: FoodSuggestionDebugSummary?
    @State private var lastMaintenanceResult: FoodMemoryMaintenanceResult?
    @State private var showsRecentEntries = true
    @State private var showsRecentMemories = false
    @State private var showsSuggestionDebug = true

    private var trackedEntries: [FoodEntry] {
        foodEntries.filter {
            $0.acceptedSnapshotData != nil || $0.foodMemoryResolutionState != .unresolved
        }
    }

    private var recentTrackedEntries: [FoodEntry] {
        Array(trackedEntries.prefix(12))
    }

    private var pendingCount: Int {
        trackedEntries.filter { $0.foodMemoryNeedsResolution }.count
    }

    private var matchedCount: Int {
        trackedEntries.filter { $0.foodMemoryResolutionState == .matched }.count
    }

    private var candidateCount: Int {
        trackedEntries.filter { $0.foodMemoryResolutionState == .createdCandidate }.count
    }

    var body: some View {
        Section {
            LabeledContent("Total Entries", value: "\(shadowSummary?.totalEntries ?? foodEntries.count)")
            LabeledContent("Tracked Entries", value: "\(shadowSummary?.trackedEntries ?? trackedEntries.count)")
            LabeledContent("Legacy Without Snapshot", value: "\(shadowSummary?.legacyEntriesWithoutSnapshot ?? legacyEntriesWithoutSnapshotCount)")
            LabeledContent("Structured Snapshot Entries", value: "\(shadowSummary?.entriesWithStructuredComponents ?? structuredEntriesCount)")
            LabeledContent("Memories", value: "\(shadowSummary?.totalMemories ?? foodMemories.count)")
            LabeledContent("Confirmed Memories", value: "\(shadowSummary?.confirmedMemories ?? confirmedMemoriesCount)")
            LabeledContent("Pending", value: "\(shadowSummary?.pendingEntries ?? pendingCount)")
            LabeledContent("Matched", value: "\(shadowSummary?.matchedEntries ?? matchedCount)")
            LabeledContent("Candidates", value: "\(shadowSummary?.candidateEntries ?? candidateCount)")
            LabeledContent("Avg Match Confidence", value: confidenceText(shadowSummary?.averageMatchConfidence ?? averageMatchConfidence))
            LabeledContent("Avg Matched Confidence", value: confidenceText(shadowSummary?.averageMatchedConfidence ?? averageMatchedConfidence))

            if let suggestionDebugSummary {
                DisclosureGroup(
                    "Current \(bucketLabel(for: suggestionDebugSummary.bucket)) Suggestion Pipeline",
                    isExpanded: $showsSuggestionDebug
                ) {
                    LabeledContent("Total Memories", value: "\(suggestionDebugSummary.totalMemories)")
                    LabeledContent("Base Eligible", value: "\(suggestionDebugSummary.baseEligibleMemories)")
                    LabeledContent("Structured Memories", value: "\(suggestionDebugSummary.structuredMemories)")
                    LabeledContent("Bucket-Aligned Memories", value: "\(suggestionDebugSummary.bucketAlignedMemories)")
                    LabeledContent("Filtered Today Match", value: "\(suggestionDebugSummary.filteredAlreadySatisfiedToday)")
                    LabeledContent("Filtered Negative Feedback", value: "\(suggestionDebugSummary.filteredNegativeFeedback)")
                    LabeledContent("Filtered Stale", value: "\(suggestionDebugSummary.filteredStale)")
                    LabeledContent("Filtered Retrieval Timing", value: "\(suggestionDebugSummary.filteredRetrievalTiming)")
                    LabeledContent("Filtered Retrieval History", value: "\(suggestionDebugSummary.filteredRetrievalHistory)")
                    LabeledContent("Filtered Session Completion", value: "\(suggestionDebugSummary.filteredLikelyCompletedSession)")
                    LabeledContent("Filtered Low Retrieval Score", value: "\(suggestionDebugSummary.filteredLowRetrievalScore)")
                    LabeledContent("Retrieved Candidates", value: "\(suggestionDebugSummary.retrievedCandidateCount)")
                    LabeledContent("Filtered Final Eligibility", value: "\(suggestionDebugSummary.filteredFinalEligibility)")
                    LabeledContent("Filtered Low Final Score", value: "\(suggestionDebugSummary.filteredLowFinalScore)")
                    LabeledContent("Shown Suggestions", value: "\(suggestionDebugSummary.finalEligibleCount)")

                    if suggestionDebugSummary.shownSuggestionTitles.isEmpty {
                        Text("No suggestions currently survive the full pipeline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(suggestionDebugSummary.shownSuggestionTitles.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastMaintenanceResult {
                Text("Last maintenance: backfilled \(lastMaintenanceResult.backfilledEntries), resolved \(lastMaintenanceResult.resolvedEntries)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                runMaintenanceNow()
            } label: {
                Text(isRunningBackfill ? "Backfilling..." : "Backfill + Resolve")
            }
            .disabled(isRunningBackfill || isRunningResolver)

            Button {
                runResolverNow()
            } label: {
                Text(isRunningResolver ? "Resolving..." : "Run Resolver Now")
            }
            .disabled(isRunningResolver || isRunningBackfill)

            DisclosureGroup("Recent Entry Decisions", isExpanded: $showsRecentEntries) {
                if recentTrackedEntries.isEmpty {
                    Text("No accepted food snapshots have been tracked yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentTrackedEntries, id: \.id) { entry in
                        DeveloperFoodMemoryEntryRow(entry: entry)
                    }
                }
            }

            DisclosureGroup("Recent Canonical Memories", isExpanded: $showsRecentMemories) {
                if foodMemories.isEmpty {
                    Text("No canonical food memories have been created yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(foodMemories.prefix(8)), id: \.id) { memory in
                        DeveloperFoodMemoryMemoryRow(memory: memory)
                    }
                }
            }
        } header: {
            Text("Food Memory Shadow Mode")
        } footer: {
            Text("This debug-only view shows how accepted food logs are resolving into canonical memories before any user-facing remembered-food UI is added.")
        }
        .task(id: foodEntries.count + foodMemories.count) {
            refreshShadowSummary()
        }
    }

    private func runResolverNow() {
        isRunningResolver = true
        Task { @MainActor in
            defer { isRunningResolver = false }
            var totalResolved = 0
            for _ in 0..<12 {
                let resolved = (try? FoodMemoryService().resolvePendingEntries(limit: 50, modelContext: modelContext)) ?? 0
                totalResolved += resolved
                if resolved == 0 {
                    break
                }
            }
            if totalResolved > 0 {
                shadowSummary = try? FoodMemoryService().shadowSummary(modelContext: modelContext)
            }
            refreshShadowSummary()
        }
    }

    private var legacyEntriesWithoutSnapshotCount: Int {
        foodEntries.filter {
            $0.acceptedSnapshotData == nil &&
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var structuredEntriesCount: Int {
        trackedEntries.filter {
            $0.acceptedComponents.contains(where: { $0.source != .derived })
        }.count
    }

    private var confirmedMemoriesCount: Int {
        foodMemories.filter { $0.status == .confirmed }.count
    }

    private var averageMatchConfidence: Double {
        guard !trackedEntries.isEmpty else { return 0 }
        return trackedEntries.map(\.foodMemoryMatchConfidence).reduce(0, +) / Double(trackedEntries.count)
    }

    private var averageMatchedConfidence: Double {
        let matchedEntries = trackedEntries.filter { $0.foodMemoryResolutionState == .matched }
        guard !matchedEntries.isEmpty else { return 0 }
        return matchedEntries.map(\.foodMemoryMatchConfidence).reduce(0, +) / Double(matchedEntries.count)
    }

    private func confidenceText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func bucketLabel(for bucket: MealTimeBucket) -> String {
        switch bucket {
        case .breakfast:
            return "Breakfast"
        case .lunch:
            return "Lunch"
        case .dinner:
            return "Dinner"
        case .lateNight:
            return "Late Night"
        case .snack:
            return "Snack"
        }
    }

    private func runMaintenanceNow() {
        isRunningBackfill = true
        Task { @MainActor in
            defer { isRunningBackfill = false }
            var totalBackfilled = 0
            var totalResolved = 0

            for _ in 0..<12 {
                let result = try? FoodMemoryService().runMaintenance(
                    backfillLimit: 100,
                    resolveLimit: 100,
                    modelContext: modelContext
                )
                let backfilled = result?.backfilledEntries ?? 0
                let resolved = result?.resolvedEntries ?? 0
                totalBackfilled += backfilled
                totalResolved += resolved

                if backfilled == 0, resolved == 0 {
                    break
                }
            }

            lastMaintenanceResult = FoodMemoryMaintenanceResult(
                backfilledEntries: totalBackfilled,
                resolvedEntries: totalResolved
            )
            refreshShadowSummary()
        }
    }

    private func refreshShadowSummary() {
        shadowSummary = try? FoodMemoryService().shadowSummary(modelContext: modelContext)
        suggestionDebugSummary = try? FoodSuggestionService().debugCameraSuggestions(
            limit: 3,
            modelContext: modelContext
        )
    }
}

private struct DeveloperOverridesSection: View {
    let billingService: BillingService
    let monetizationService: MonetizationService
    let appAccountService: AppAccountService
    let debugPlanBinding: Binding<SubscriptionPlan>
    let debugPlanPreviewBinding: Binding<Bool>
    let debugSyncStateBinding: Binding<BillingSyncState>
    let debugIdentityBinding: Binding<AppAccountIdentityMode>
    let debugBackendBinding: Binding<BackendEnvironment>
    let debugAIProviderOverrideBinding: Binding<AIProviderOverride>

    var body: some View {
        Section {
            Toggle("Use Local Plan Preview", isOn: debugPlanPreviewBinding)

            if billingService.isDebugPlanPreviewEnabled {
                Picker("Preview Plan", selection: debugPlanBinding) {
                    ForEach(SubscriptionPlan.allCases) { plan in
                        Text(plan.displayName).tag(plan)
                    }
                }
            }

            Picker("Billing Sync", selection: debugSyncStateBinding) {
                ForEach(BillingSyncState.allCases, id: \.self) { state in
                    Text(state.displayName).tag(state)
                }
            }

            Picker("Identity", selection: debugIdentityBinding) {
                ForEach(AppAccountIdentityMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Backend", selection: debugBackendBinding) {
                ForEach(BackendEnvironment.allCases, id: \.self) { environment in
                    Text(environment.displayName).tag(environment)
                }
            }

            Picker("AI Provider", selection: debugAIProviderOverrideBinding) {
                ForEach(AIProviderOverride.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            LabeledContent("Quota Reset") {
                Text(monetizationService.nextResetDate, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }

            Button("Reset AI Quota") {
                monetizationService.resetQuotaForDebug()
            }
        } header: {
            Text("Developer Overrides")
        } footer: {
            Text("These are QA-only overrides. Local plan preview changes UI state, and the AI provider picker only affects debug AI requests against non-production backends.")
        }
    }
}

private struct DeveloperFoodMemoryEntryRow: View {
    let entry: FoodEntry

    private var stateText: String {
        switch entry.foodMemoryResolutionState {
        case .unresolved:
            return "Unresolved"
        case .queued:
            return "Queued"
        case .matched:
            return "Matched"
        case .createdCandidate:
            return "Candidate"
        case .rejected:
            return "Rejected"
        }
    }

    private var confidenceText: String {
        "\(Int((entry.foodMemoryMatchConfidence * 100).rounded()))%"
    }

    private var memoryText: String {
        guard let foodMemoryIdString = entry.foodMemoryIdString,
              !foodMemoryIdString.isEmpty else {
            return "None"
        }
        return String(foodMemoryIdString.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .fontWeight(.semibold)
                Spacer()
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(entry.loggedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(confidenceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = entry.acceptedSnapshot {
                Text(snapshot.normalizedDisplayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Memory", value: memoryText)
                .font(.footnote)

            if let explanation = entry.foodMemoryResolutionExplanation {
                if !explanation.topSignals.isEmpty {
                    Text(explanation.topSignals.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !explanation.penalties.isEmpty {
                    Text(explanation.penalties.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DeveloperFoodMemoryMemoryRow: View {
    let memory: FoodMemory

    private var aliasText: String {
        let displayNames = memory.aliases.map(\.displayName)
        guard !displayNames.isEmpty else { return "No aliases" }
        return displayNames.prefix(3).joined(separator: " • ")
    }

    private var componentText: String {
        let names = memory.components.map(\.normalizedName)
        guard !names.isEmpty else { return "No components" }
        return names.prefix(4).joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(memory.displayName)
                    .fontWeight(.semibold)
                Spacer()
                Text(memory.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Obs \(memory.observationCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Reuse \(memory.confirmedReuseCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(aliasText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(componentText)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
#endif

private struct DeveloperSummaryRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
            }

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct SubscriptionProductRow: View {
    let product: SubscriptionProductDefinition
    let isCurrentPlan: Bool
    let isLoadingPurchase: Bool
    let canSubscribe: Bool
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.displayName)
                    .fontWeight(product.isPrimaryOffer ? .semibold : .regular)
                Spacer()
                if isCurrentPlan {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if product.isPrimaryOffer {
                    Text("Recommended")
                        .font(.caption)
                        .foregroundStyle(.accent)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(product.subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isCurrentPlan {
                    Button(action: onSubscribe) {
                        Text(isLoadingPurchase ? "Purchasing..." : "Subscribe")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSubscribe)
                }
            }

            Text(product.marketingPoints.joined(separator: " • "))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
            .environment(AppAccountService.shared)
            .environment(AccountSessionService.shared)
            .environment(BillingService.shared)
            .environment(MonetizationService.shared)
    }
}
