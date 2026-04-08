import SwiftUI
import AuthenticationServices

enum AccountSetupContext: String, Identifiable {
    case secureExistingData
    case billing
    case restorePurchases
    case aiFeatures

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .secureExistingData:
            "Trai Account"
        case .billing:
            "Billing"
        case .restorePurchases:
            "Restore"
        case .aiFeatures:
            "AI Access"
        }
    }

    var title: String {
        switch self {
        case .secureExistingData:
            "Finish setting up your Trai account"
        case .billing:
            "Sign in before subscribing"
        case .restorePurchases:
            "Sign in before restoring purchases"
        case .aiFeatures:
            "Sign in to use server-backed Trai AI"
        }
    }

    var message: String {
        switch self {
        case .secureExistingData:
            "Sign in with Apple to connect this device to your Trai account."
        case .billing:
            "Connect your Trai account before starting a subscription."
        case .restorePurchases:
            "Connect your Trai account before restoring purchases."
        case .aiFeatures:
            "Connect your Trai account to use server-backed Trai AI."
        }
    }

    var secondaryMessage: String {
        switch self {
        case .secureExistingData:
            "Your existing logs and profile stay on this device."
        case .billing:
            "Your existing logs and profile stay on this device."
        case .restorePurchases:
            "Your existing logs and profile stay on this device."
        case .aiFeatures:
            "Your existing logs and profile stay on this device."
        }
    }
}

struct AccountSetupView: View {
    let context: AccountSetupContext
    var showsDismissButton = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?
    @AppStorage("account_setup_prompt_last_dismissed_at") private var accountSetupPromptLastDismissedAt: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AccountSetupHero(context: context)
                    .padding(.top, 18)

                Spacer(minLength: 0)

                AccountSetupBottomContent(
                    secondaryMessage: context.secondaryMessage,
                    blockedReason: appAccountService?.realAccountSignInBlockedReason,
                    backendActionTitle: backendActionTitle,
                    lastErrorMessage: accountSessionService?.lastErrorMessage,
                    accountSessionService: accountSessionService,
                    onSwitchBackend: switchToRecommendedBackend,
                    onAppleSignIn: handleAppleSignIn
                )
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .navigationTitle("Account Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not Now", systemImage: "xmark") {
                            handleDismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: accountSessionService?.isAuthenticated ?? false) { _, isAuthenticated in
            guard isAuthenticated else { return }
            dismiss()
        }
        .tint(TraiColors.brandAccent)
        .accentColor(TraiColors.brandAccent)
    }

    private var backendActionTitle: String? {
        guard let recommendedEnvironment = appAccountService?.recommendedBackendEnvironmentForRealAccountSignIn else {
            return nil
        }
        return "Use \(recommendedEnvironment.displayName)"
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

    private func handleDismiss() {
        if context == .secureExistingData {
            accountSetupPromptLastDismissedAt = Date().timeIntervalSince1970
        }
        dismiss()
    }

    private func switchToRecommendedBackend() {
        guard let recommendedEnvironment = appAccountService?.recommendedBackendEnvironmentForRealAccountSignIn else {
            return
        }
        appAccountService?.setBackendEnvironment(recommendedEnvironment)
    }
}

private struct AccountSetupHero: View {
    let context: AccountSetupContext

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(TraiColors.brandAccent.opacity(0.12))
                    .frame(width: 124, height: 124)
                    .blur(radius: 14)

                TraiLensView(size: 78, state: .thinking, palette: .energy)
            }

            VStack(spacing: 10) {
                Text(context.title)
                    .font(.traiBold(30))
                    .multilineTextAlignment(.center)

                Text(context.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

private struct AccountSetupBottomContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let secondaryMessage: String
    let blockedReason: String?
    let backendActionTitle: String?
    let lastErrorMessage: String?
    let accountSessionService: AccountSessionService?
    let onSwitchBackend: () -> Void
    let onAppleSignIn: (Result<ASAuthorization, any Error>, AccountSessionService) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(secondaryMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)

            if let lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }

            if let blockedReason {
                BackendRequirementCard(
                    message: blockedReason,
                    actionTitle: backendActionTitle,
                    action: onSwitchBackend
                )
            } else if let accountSessionService {
                SignInWithAppleButton(.signIn) { request in
                    accountSessionService.configureAppleSignInRequest(request)
                } onCompletion: { result in
                    onAppleSignIn(result, accountSessionService)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
            }
        }
    }
}

#Preview {
    AccountSetupView(context: .secureExistingData, showsDismissButton: false)
        .environment(AppAccountService.shared)
        .environment(AccountSessionService.shared)
}
