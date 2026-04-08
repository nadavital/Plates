import SwiftUI
import AuthenticationServices

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
                debugBackendBinding: debugBackendBinding(for: appAccountService)
            )
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
private struct DeveloperOverridesSection: View {
    let billingService: BillingService
    let monetizationService: MonetizationService
    let appAccountService: AppAccountService
    let debugPlanBinding: Binding<SubscriptionPlan>
    let debugPlanPreviewBinding: Binding<Bool>
    let debugSyncStateBinding: Binding<BillingSyncState>
    let debugIdentityBinding: Binding<AppAccountIdentityMode>
    let debugBackendBinding: Binding<BackendEnvironment>

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
            Text("These are QA-only overrides. Local plan preview changes UI state, but backend AI and billing still follow the real server entitlement.")
        }
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
