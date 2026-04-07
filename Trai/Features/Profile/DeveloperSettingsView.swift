import SwiftUI
import AuthenticationServices

struct DeveloperSettingsView: View {
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @State private var presentedAccountSetupContext: AccountSetupContext?

    private var hasCurrentPaidSubscription: Bool {
        guard let billingService else { return false }
        return billingService.availableProducts.contains { billingService.isCurrentPaidPlan($0.plan) }
    }

    var body: some View {
        List {
            accountOverviewSection
            accountAccessSection
            subscriptionOffersSection
            debugSection
        }
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
        }
    }

    @ViewBuilder
    private var accountOverviewSection: some View {
        Section {
            if let accountSessionService {
                LabeledContent("Session", value: accountSessionService.sessionStatusText)
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
                LabeledContent("Backend", value: appAccountService.backendStatusText)
            }

            if let billingService {
                LabeledContent("Billing Sync", value: billingService.syncStatusDescription)
                LabeledContent("App Store", value: billingService.storeKitStatusDescription)
            }

            if let monetizationService {
                LabeledContent("Plan", value: monetizationService.currentPlanDisplayText)
                LabeledContent("AI Features", value: monetizationService.aiAccessSummaryText)
            }

            if appAccountService == nil && billingService == nil && monetizationService == nil {
                Text("Billing state unavailable")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Account & Billing")
        } footer: {
            Text("Local development controls for account state, billing sync, and current entitlements.")
        }
    }

    @ViewBuilder
    private var accountAccessSection: some View {
        if let accountSessionService, let appAccountService {
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
                    Button(action: refreshAccountState) {
                        Text(accountSessionService.isSyncingAccount ? "Syncing Account..." : "Refresh Account State")
                    }
                    .disabled(accountSessionService.isSyncingAccount)

                    Button("Sign Out", role: .destructive) {
                        accountSessionService.signOut()
                    }
                } else if let blockedReason = appAccountService.realAccountSignInBlockedReason {
                    BackendRequirementCard(
                        message: blockedReason,
                        actionTitle: backendActionTitle(for: appAccountService),
                        action: {
                            switchToRecommendedBackend(using: appAccountService)
                        }
                    )
                } else {
                    SignInWithAppleButton(.signIn, onRequest: accountSessionService.configureAppleSignInRequest) { result in
                        handleAppleSignIn(result, using: accountSessionService)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                }
            } header: {
                Text("Account Access")
            } footer: {
                if appAccountService.backendEnvironment == .localDevelopment {
                    Text("For on-device testing, enter a reachable backend URL like your Mac's LAN IP or a tunnel. Example: `http://192.168.1.23:8789`.")
                } else {
                    Text("Use this screen to test sign-in, account refresh, and authenticated billing flows without surfacing those controls in the main settings.")
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionOffersSection: some View {
        if let billingService, !billingService.availableProducts.isEmpty {
            Section {
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
                            subscribe(to: product.id)
                        }
                    )
                }

                Button(action: loadStoreKitProducts) {
                    Text(billingService.isLoadingProducts ? "Loading Products..." : "Load App Store Products")
                }
                .disabled(billingService.isLoadingProducts || billingService.purchaseInFlightProductID != nil)

                Button(action: restorePurchases) {
                    Text(billingService.isRestoringPurchases ? "Restoring..." : "Restore Purchases")
                }
                .disabled(billingService.isRestoringPurchases || billingService.purchaseInFlightProductID != nil)

                if hasCurrentPaidSubscription, let manageSubscriptionsURL = billingService.manageSubscriptionsURL {
                    Link("Manage Subscription", destination: manageSubscriptionsURL)
                }
            } header: {
                Text("Subscription Offers")
            } footer: {
                Text("Configured App Store product IDs: \(billingService.productIdentifiers.joined(separator: ", ")).")
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
#if DEBUG
        if let monetizationService, let billingService, let appAccountService {
            Section {
                LabeledContent("AI Transport", value: monetizationService.aiTransportMode.displayName)
                LabeledContent("Usage", value: monetizationService.quotaSummaryText)
                LabeledContent("Quota Reset") {
                    Text(monetizationService.nextResetDate, format: .dateTime.month().day())
                        .foregroundStyle(.secondary)
                }

                Picker("Debug Plan", selection: debugPlanBinding(for: billingService, monetizationService: monetizationService)) {
                    ForEach(SubscriptionPlan.allCases) { plan in
                        Text(plan.displayName).tag(plan)
                    }
                }

                Picker("Billing Sync", selection: debugSyncStateBinding(for: billingService)) {
                    ForEach(BillingSyncState.allCases, id: \.self) { state in
                        Text(state.displayName).tag(state)
                    }
                }

                Picker("AI Transport", selection: debugTransportBinding(for: billingService, monetizationService: monetizationService)) {
                    ForEach(AITransportMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Identity", selection: debugIdentityBinding(for: appAccountService)) {
                    ForEach(AppAccountIdentityMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Backend", selection: debugBackendBinding(for: appAccountService)) {
                    ForEach(BackendEnvironment.allCases, id: \.self) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }

                Button("Reset AI Quota") {
                    monetizationService.resetQuotaForDebug()
                }
            } header: {
                Text("Billing Debug")
            } footer: {
                Text("Debug-only controls for exercising account, paywall, backend, and quota states before the production billing flow is finalized.")
            }
        }
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

    private func debugSyncStateBinding(for billingService: BillingService) -> Binding<BillingSyncState> {
        Binding(
            get: { billingService.syncState },
            set: { billingService.setDebugSyncState($0) }
        )
    }

    private func debugTransportBinding(
        for billingService: BillingService,
        monetizationService: MonetizationService
    ) -> Binding<AITransportMode> {
        Binding(
            get: { monetizationService.aiTransportMode },
            set: { billingService.setDebugTransportMode($0) }
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
#endif
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
