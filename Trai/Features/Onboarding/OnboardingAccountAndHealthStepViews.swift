//
//  OnboardingAccountAndHealthStepViews.swift
//  Trai
//
//  Account setup and Apple Health onboarding steps.
//

import SwiftUI
import AuthenticationServices

struct AccountOnboardingStepView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                onboardingHeader(
                    title: "Connect your Trai account",
                    subtitle: "Sign in with Apple before plan choices so your Trai Pro access and future plan changes stay attached to your account."
                )

                if accountSessionService?.isAuthenticated == true {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text(accountSessionService?.currentUserDisplayName ?? "Connected")
                            .font(.body)

                        Text("You’re all set. We’ll use this account for subscriptions and server-backed Trai features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    accountSetupCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var accountSetupCard: some View {
        VStack(spacing: 16) {
            Text("Recommended, not required")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground), in: Capsule())

            if let blockedReason = appAccountService?.realAccountSignInBlockedReason {
                BackendRequirementCard(
                    message: blockedReason,
                    actionTitle: backendActionTitle,
                    action: switchToRecommendedBackend
                )
            } else if let accountSessionService {
                SignInWithAppleButton(.signIn) { request in
                    accountSessionService.configureAppleSignInRequest(request)
                } onCompletion: { result in
                    handleAppleSignIn(result, using: accountSessionService)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
            }

            Text("Your current logs and profile stay on this device either way.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let lastErrorMessage = accountSessionService?.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var backendActionTitle: String? {
        guard let recommendedEnvironment = appAccountService?.recommendedBackendEnvironmentForRealAccountSignIn else {
            return nil
        }
        return "Use \(recommendedEnvironment.displayName)"
    }

    private func switchToRecommendedBackend() {
        guard let recommendedEnvironment = appAccountService?.recommendedBackendEnvironmentForRealAccountSignIn else {
            return
        }
        appAccountService?.setBackendEnvironment(recommendedEnvironment)
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
}

struct HealthSyncStepView: View {
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    @Binding var syncFoodToHealthKit: Bool
    @Binding var syncWeightToHealthKit: Bool
    @Binding var isRequestingHealthAccess: Bool
    @Binding var healthSyncError: String?

    let onConnect: () -> Void

    private var isConnected: Bool {
        healthKitService?.isAuthorized == true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                onboardingHeader(
                    title: "Sync with Apple Health",
                    subtitle: "Choose what Trai should send to Health during onboarding so logging and trends feel connected from the start."
                )

                VStack(alignment: .leading, spacing: 18) {
                    healthToggle(
                        title: "Sync food to Health",
                        subtitle: "Save calories and macros to Apple Health when you log meals in Trai.",
                        systemImage: "fork.knife",
                        isOn: $syncFoodToHealthKit
                    )

                    healthToggle(
                        title: "Sync weight to Health",
                        subtitle: "Keep weight entries aligned between Trai and Apple Health.",
                        systemImage: "scalemass.fill",
                        isOn: $syncWeightToHealthKit
                    )
                }
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(spacing: 14) {
                    Button(action: onConnect) {
                        HStack(spacing: 8) {
                            if isRequestingHealthAccess {
                                ProgressView()
                                    .controlSize(.small)
                            } else if isConnected {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Image(systemName: "heart.fill")
                            }

                            Text(isConnected ? "Apple Health Connected" : "Connect Apple Health")
                        }
                    }
                    .buttonStyle(.traiSecondary(color: .accentColor, fullWidth: false, fillOpacity: 0.16))
                    .disabled(isRequestingHealthAccess || isConnected || (!syncFoodToHealthKit && !syncWeightToHealthKit))

                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let healthSyncError {
                        Text(healthSyncError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var statusText: String {
        if isConnected {
            return "Trai has Health access. Your selected sync options will be saved when onboarding finishes."
        }
        if !syncFoodToHealthKit && !syncWeightToHealthKit {
            return "Turn on at least one sync option if you want Trai to write data to Apple Health."
        }
        return "Health connection is optional, but this is the best time to enable it intentionally."
    }

    private func healthToggle(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.accentColor)
    }
}

@ViewBuilder
private func onboardingHeader(title: String, subtitle: String) -> some View {
    VStack(spacing: 12) {
        TraiLensView(size: 54, state: .thinking, palette: .energy)

        Text(title)
            .font(.traiBold(28))
            .multilineTextAlignment(.center)

        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
