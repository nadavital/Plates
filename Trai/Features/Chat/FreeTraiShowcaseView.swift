import SwiftUI

struct FreeTraiShowcaseView: View {
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(\.openURL) private var openURL

    @State private var hasRequestedProducts = false
    @State private var selectedFeatureIndex = 0
    @State private var presentedAccountSetupContext: AccountSetupContext?

    private struct ShowcaseFeature: Identifiable {
        let id = UUID()
        let eyebrow: String
        let title: String
        let description: String
        let visual: Visual

        enum Visual {
            case coach
            case lens
            case plan
        }
    }

    private let features: [ShowcaseFeature] = [
        ShowcaseFeature(
            eyebrow: "Coach Chat",
            title: "Ask Trai for real-world coaching",
            description: "Get help with consistency, meal decisions, training questions, and what to do next when life gets messy.",
            visual: .coach
        ),
        ShowcaseFeature(
            eyebrow: "Trai Lens",
            title: "Snap meals and log faster",
            description: "Use the camera to analyze food, estimate macros, and keep tracking friction low when you are on the move.",
            visual: .lens
        ),
        ShowcaseFeature(
            eyebrow: "Adaptive Plans",
            title: "Build plans that actually fit you",
            description: "Create nutrition and workout plans around your goals, then refine them with Trai as your routine changes.",
            visual: .plan
        )
    ]

    private var product: SubscriptionProductDefinition {
        billingService?.recommendedProduct ?? SubscriptionProductDefinition(
            id: "trai.pro.monthly",
            plan: .pro,
            displayName: "Trai Pro",
            priceDisplay: "$3.99",
            billingPeriodLabel: "per month",
            monthlyAIUnits: SubscriptionPlan.pro.monthlyAIUnits,
            isPrimaryOffer: true,
            marketingPoints: [
                "Chat with Trai anytime",
                "Analyze food photos in seconds",
                "Create and refine personalized plans"
            ]
        )
    }

    private var currentFeature: ShowcaseFeature {
        features[selectedFeatureIndex]
    }

    private var highlightColor: Color { .accentColor }

    private var primaryButtonTitle: String {
        if let billingService, billingService.purchaseInFlightProductID == product.id {
            return "Starting Trai Pro..."
        }
        return "Start Trai Pro for \(product.priceDisplay)/month"
    }

    private var secondaryStatusText: String? {
        billingService?.storeKitUpsellMessage
    }

    private var primaryActionDisabled: Bool {
        guard let billingService else { return true }
        if billingService.isLoadingProducts || billingService.isRestoringPurchases {
            return true
        }
        return billingService.purchaseInFlightProductID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    heroSection
                    featureCarousel
                    valueSection
                    actionSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Trai")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard !hasRequestedProducts else { return }
            hasRequestedProducts = true
            await billingService?.refreshStoreKitProductsIfNeeded(force: false)
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
        }
        .task {
            guard features.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.2))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        selectedFeatureIndex = (selectedFeatureIndex + 1) % features.count
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(highlightColor.opacity(0.10))
                    .frame(width: 132, height: 132)
                    .blur(radius: 12)

                TraiLensView(size: 84, state: .thinking, palette: .energy)
            }
            .padding(.top, 4)

            VStack(spacing: 10) {
                Text("Trai Pro")
                    .font(.traiHero(32))

                Text("Your adaptive fitness coach")
                    .font(.traiHeadline(20))
                    .multilineTextAlignment(.center)

                Text("Free keeps tracking manual and focused. Trai Pro adds coach chat, Trai Lens, and adaptive planning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var featureCarousel: some View {
        VStack(spacing: 16) {
            TabView(selection: $selectedFeatureIndex) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    featureCard(feature)
                        .tag(index)
                        .padding(.horizontal, 2)
                }
            }
            .frame(height: 288)
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(features.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedFeatureIndex ? highlightColor : Color(.tertiarySystemFill))
                        .frame(width: index == selectedFeatureIndex ? 22 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: selectedFeatureIndex)
                }
            }
        }
    }

    private func featureCard(_ feature: ShowcaseFeature) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.eyebrow.uppercased())
                    .font(.traiLabel(12))
                    .tracking(1.1)
                    .foregroundStyle(highlightColor)

                Text(feature.title)
                    .font(.traiBold(23))
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                switch feature.visual {
                case .coach:
                    coachPreview
                case .lens:
                    lensPreview
                case .plan:
                    planPreview
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(highlightColor.opacity(0.08), lineWidth: 1)
        )
    }

    private var coachPreview: some View {
        VStack(spacing: 12) {
            previewBubble(
                "I’ve eaten well all day and now I want takeout. What should I do?",
                isUser: true
            )
            previewBubble(
                "Go for it, just anchor it. Pick something you’ll actually enjoy, add protein, and I’ll help you keep the rest of the day balanced.",
                isUser: false
            )
            previewBubble(
                "Tomorrow we can tighten breakfast and lunch instead of turning tonight into a guilt spiral.",
                isUser: false,
                accent: true
            )
        }
    }

    private var lensPreview: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [TraiColors.flame.opacity(0.18), TraiColors.blaze.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.macro")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(highlightColor)
                        Text("Trai Lens")
                            .font(.traiHeadline(17))
                    }
                }
                .frame(width: 104, height: 132)

            VStack(alignment: .leading, spacing: 12) {
                showcaseMetric("Chicken burrito bowl", detail: "Estimated from photo")
                showcaseMetric("690 kcal", detail: "54g protein • 68g carbs • 22g fat")
                showcaseMetric("Logged in seconds", detail: "Fast enough for real life")
            }
        }
    }

    private var planPreview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                planPreviewCard(
                    title: "Nutrition",
                    subtitle: "2,150 kcal",
                    detail: "High-protein cut with training day adjustments"
                )
                planPreviewCard(
                    title: "Workout",
                    subtitle: "4-day split",
                    detail: "Balanced around your schedule and available equipment"
                )
            }

            HStack(spacing: 8) {
                featurePill("Refine with Trai")
                featurePill("Adjust over time")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free still includes")
                .font(.traiHeadline(20))

            VStack(spacing: 10) {
                valueRow(
                    icon: "fork.knife",
                    title: "Manual nutrition tracking",
                    detail: "Log meals, calories, and macros."
                )
                valueRow(
                    icon: "figure.strengthtraining.traditional",
                    title: "Workout tracking",
                    detail: "Track sessions, sets, and progress."
                )
                valueRow(
                    icon: "heart.text.square",
                    title: "Core app experience",
                    detail: "Use HealthKit, widgets, and reminders."
                )
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actionSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text("Unlock Trai Pro")
                        .font(.traiHeadline(20))

                    Text("\(product.priceDisplay) / month")
                        .font(.traiHeadline(18))
                        .foregroundStyle(highlightColor)

                    Text("Cancel anytime. App Store billing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    handlePrimaryAction()
                } label: {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiPrimary(color: highlightColor, size: .large, fullWidth: true))
                .disabled(primaryActionDisabled)

                HStack(spacing: 10) {
                    Button("Restore Purchases") {
                        guard accountSessionService?.isAuthenticated == true else {
                            presentedAccountSetupContext = .restorePurchases
                            return
                        }
                        Task {
                            await billingService?.restorePurchases()
                        }
                    }
                    .buttonStyle(.traiSecondary(color: highlightColor, fullWidth: true, fillOpacity: 0.12))
                    .disabled(billingService?.isRestoringPurchases == true)

                    if let manageSubscriptionsURL = billingService?.manageSubscriptionsURL {
                        Button("Manage") {
                            openURL(manageSubscriptionsURL)
                        }
                        .buttonStyle(.traiTertiary(color: highlightColor, fullWidth: true))
                    }
                }

                if let secondaryStatusText {
                    Text(secondaryStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(highlightColor.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func previewBubble(_ text: String, isUser: Bool, accent: Bool = false) -> some View {
        let bubbleColor: Color =
            if isUser {
                .accentColor
            } else if accent {
                highlightColor.opacity(0.12)
            } else {
                Color(.systemBackground)
            }

        return HStack {
            if isUser { Spacer(minLength: 36) }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent ? highlightColor.opacity(0.18) : .clear, lineWidth: 1)
                )
            if !isUser { Spacer(minLength: 36) }
        }
    }

    private func showcaseMetric(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.traiHeadline(15))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func planPreviewCard(title: String, subtitle: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.traiLabel(12))
                .foregroundStyle(highlightColor)
            Text(subtitle)
                .font(.traiHeadline(18))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func valueRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(highlightColor)
                .frame(width: 36, height: 36)
                .background(highlightColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.traiHeadline(16))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func featurePill(_ title: String) -> some View {
        Text(title)
            .font(.traiLabel(11))
            .foregroundStyle(highlightColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(highlightColor.opacity(0.10), in: Capsule())
    }

    private func handlePrimaryAction() {
        guard let billingService else { return }
        guard accountSessionService?.isAuthenticated == true else {
            presentedAccountSetupContext = .billing
            return
        }

        Task {
            if !billingService.isStoreKitProductLoaded(for: product.id) {
                await billingService.loadStoreKitProducts()
            }
            await billingService.purchase(productID: product.id)
        }
    }
}

#Preview {
    FreeTraiShowcaseView()
        .environment(BillingService.shared)
}
