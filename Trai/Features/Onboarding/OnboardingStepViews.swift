//
//  OnboardingStepViews.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import AuthenticationServices
import SwiftUI

// MARK: - Welcome Step

struct WelcomeStepView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @State private var heroVisible = false
    @State private var titleVisible = false
    @State private var actionVisible = false
    @State private var didRefreshAccess = false
    @State private var demoIndex = 0

    let onContinue: () -> Void

    var body: some View {
        ZStack {
            floatingDecorations

            VStack(spacing: 22) {
                Spacer(minLength: 30)
                heroSection
                AnimatedTraiDemo(index: demoIndex)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 16)
                Spacer(minLength: 150)
            }
            .padding(.horizontal, 24)

            VStack {
                Spacer()
                accountSection
                    .opacity(actionVisible ? 1 : 0)
                    .offset(y: actionVisible ? 0 : 24)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            startEntranceAnimations()
        }
        .task {
            await cycleDemoMoments()
        }
        .task {
            guard !didRefreshAccess else { return }
            didRefreshAccess = true
            #if DEBUG
            if AppLaunchArguments.shouldRunOnboardingFlowUITest {
                return
            }
            #endif
            await billingService?.refreshAccessStateForImmediateUse()
        }
    }

    private func startEntranceAnimations() {
        withAnimation(.easeOut(duration: 0.5)) {
            heroVisible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            actionVisible = true
        }
    }

    private func cycleDemoMoments() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.45)) {
                    demoIndex = (demoIndex + 1) % TraiDemoMoment.moments.count
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 16) {
            TraiLensView(size: 112, state: .idle, palette: .energy, breathes: false)
                .opacity(heroVisible ? 1 : 0)
                .scaleEffect(heroVisible ? 1 : 0.86)

            Text("Trai")
                .font(.traiHero(54))
                .foregroundStyle(.primary)
                .opacity(titleVisible ? 1 : 0)

            Text("Your AI coach for food, fitness, and progress.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(titleVisible ? 1 : 0)
        }
    }

    private var accountSection: some View {
        VStack(spacing: 10) {
            if let lastErrorMessage = accountSessionService?.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            if AppLaunchArguments.shouldRunOnboardingFlowUITest {
                Button(action: onContinue) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiPrimary(color: TraiColors.brandAccent, size: .large, fullWidth: true))
            } else if accountSessionService?.isAuthenticated == true {
                signedInContinueButton
            } else if let blockedReason = appAccountService?.realAccountSignInBlockedReason {
                BackendRequirementCard(
                    message: blockedReason,
                    actionTitle: backendActionTitle,
                    action: switchToRecommendedBackend
                )
            } else if let accountSessionService {
                appleSignInButton(accountSessionService)
            }
            #else
            if accountSessionService?.isAuthenticated == true {
                signedInContinueButton
            } else if let blockedReason = appAccountService?.realAccountSignInBlockedReason {
                BackendRequirementCard(
                    message: blockedReason,
                    actionTitle: backendActionTitle,
                    action: switchToRecommendedBackend
                )
            } else if let accountSessionService {
                appleSignInButton(accountSessionService)
            }
            #endif
        }
    }

    private var signedInContinueButton: some View {
        VStack(spacing: 10) {
            Label(signedInMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiPrimary(color: TraiColors.brandAccent, size: .large, fullWidth: true))
        }
    }

    private func appleSignInButton(_ accountSessionService: AccountSessionService) -> some View {
        SignInWithAppleButton(.signIn) { request in
            accountSessionService.configureAppleSignInRequest(request)
        } onCompletion: { result in
            handleAppleSignIn(result, using: accountSessionService)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 54)
    }

    private var signedInMessage: String {
        if monetizationService?.canAccessAIFeatures == true {
            return "Signed in. Trai Pro is active."
        }
        return "Signed in. Your plan will stay with your account."
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

    private var floatingDecorations: some View {
        Color.clear
    }
}

struct OnboardingTraiHeader: View {
    let title: String
    var lensSize: CGFloat = 54
    var lensState: TraiLensState = .idle
    var lensBreathes = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TraiLensView(size: lensSize, state: lensState, palette: .energy, breathes: lensBreathes)

            StreamingText(text: title)
                .font(.traiBold(26))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(minHeight: 64, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TraiDemoMoment {
    let icon: String
    let title: String
    let userText: String
    let traiText: String
    let tint: Color

    static let moments: [TraiDemoMoment] = [
        TraiDemoMoment(
            icon: "camera.fill",
            title: "Log meals fast",
            userText: "Chicken bowl with rice and avocado",
            traiText: "Logged. I’ll keep your day balanced.",
            tint: TraiColors.flame
        ),
        TraiDemoMoment(
            icon: "target",
            title: "Build targets",
            userText: "I want to get leaner and stronger",
            traiText: "Got it. I’ll build around recomposition.",
            tint: .accentColor
        ),
        TraiDemoMoment(
            icon: "sparkles",
            title: "Adapt daily",
            userText: "Dinner was heavier than planned",
            traiText: "No problem. I’ll adjust what’s left today.",
            tint: TraiColors.coral
        )
    ]
}

private struct AnimatedTraiDemo: View {
    let index: Int

    private var moment: TraiDemoMoment {
        TraiDemoMoment.moments[index % TraiDemoMoment.moments.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                DemoBubble(text: moment.userText, alignment: .trailing, tint: Color(.systemGray5))
                TraiDemoReply(icon: moment.icon, title: moment.title, text: moment.traiText, tint: moment.tint)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(TraiColors.brandAccent.opacity(0.12)), in: .rect(cornerRadius: 24))
    }
}

private struct TraiDemoReply: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.18), in: .rect(cornerRadius: 16))

            Spacer(minLength: 30)
        }
    }
}

struct StreamingText: View {
    let text: String
    var intervalNanoseconds: UInt64 = 36_000_000

    @State private var visibleCount = 0

    var body: some View {
        Text(String(text.prefix(visibleCount)))
            .task(id: text) {
                visibleCount = 0
                for index in 1...text.count {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: intervalNanoseconds)
                    await MainActor.run {
                        visibleCount = index
                    }
                }
            }
    }
}

private struct DemoBubble: View {
    enum BubbleAlignment {
        case leading
        case trailing
    }

    let text: String
    let alignment: BubbleAlignment
    let tint: Color

    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 36)
            }

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(tint.opacity(alignment == .trailing ? 0.72 : 0.18), in: .rect(cornerRadius: 16))

            if alignment == .leading {
                Spacer(minLength: 36)
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    WelcomeStepView(onContinue: {})
}
