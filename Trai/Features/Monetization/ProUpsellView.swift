import SwiftUI

struct ProUpsellBenefit: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

enum ProUpsellSource: String, Identifiable {
    case chat
    case foodAnalysis
    case nutritionPlan
    case workoutPlan
    case exerciseAnalysis
    case settings

    var id: String { rawValue }

    // Same four capabilities every time — source only determines order.
    var benefits: [ProUpsellBenefit] {
        let coaching = ProUpsellBenefit(
            icon: "circle.hexagongrid.circle",
            title: "A coach that acts",
            description: "Ask about food, workouts, or goals. Trai understands and follows through."
        )
        let logging = ProUpsellBenefit(
            icon: "fork.knife",
            title: "Instant food logging",
            description: "Snap a photo. Trai identifies and logs it in seconds."
        )
        let plans = ProUpsellBenefit(
            icon: "calendar.badge.checkmark",
            title: "Personalized plans",
            description: "Nutrition and training plans built around your real goals."
        )
        let suggestions = ProUpsellBenefit(
            icon: "sparkles",
            title: "Smart suggestions",
            description: "Proactive nudges and insights when they matter most."
        )

        switch self {
        case .chat, .settings:
            return [coaching, logging, plans, suggestions]
        case .foodAnalysis:
            return [logging, coaching, plans, suggestions]
        case .nutritionPlan:
            return [plans, logging, coaching, suggestions]
        case .workoutPlan:
            return [plans, coaching, logging, suggestions]
        case .exerciseAnalysis:
            return [coaching, plans, logging, suggestions]
        }
    }
}

struct ProUpsellView: View {
    let source: ProUpsellSource
    var showsDismissButton = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @State private var hasRequestedProducts = false
    @State private var presentedAccountSetupContext: AccountSetupContext?

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

    private var primaryButtonTitle: String {
        if let billingService, billingService.purchaseInFlightProductID == product.id {
            return "Unlocking Pro..."
        }
        return "Get Trai Pro"
    }

    private var isPurchaseDisabled: Bool {
        guard let billingService else { return true }
        return billingService.isLoadingProducts
            || billingService.isRestoringPurchases
            || billingService.purchaseInFlightProductID != nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [TraiColors.brandAccent.opacity(0.07), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ProUpsellHero()
                            .padding(.top, showsDismissButton ? 58 : 28)

                        Spacer(minLength: 44)

                        ProUpsellBenefitList(benefits: source.benefits)

                        Spacer(minLength: 40)

                        ProUpsellPurchaseCard(
                            product: product,
                            primaryButtonTitle: primaryButtonTitle,
                            isPurchaseDisabled: isPurchaseDisabled,
                            isRestoreDisabled: billingService?.isRestoringPurchases == true,
                            errorMessage: billingService?.storeKitUpsellMessage,
                            troubleshootingMessage: nil,
                            onPurchase: handlePurchase,
                            onRestore: handleRestore
                        )
                        .padding(.bottom, 28)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, 20)
                }

                if showsDismissButton {
                    Button("Dismiss", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                }
            }
        }
        .task {
            guard !hasRequestedProducts else { return }
            hasRequestedProducts = true
            guard let billingService else { return }
            await billingService.refreshStoreKitProductsIfNeeded(force: false)
        }
        .onChange(of: monetizationService?.canAccessAIFeatures ?? false) { _, hasAccess in
            guard hasAccess, showsDismissButton else { return }
            dismiss()
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
        }
        .tint(TraiColors.brandAccent)
        .accentColor(TraiColors.brandAccent)
    }

    private func handlePurchase() {
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

    private func handleRestore() {
        guard accountSessionService?.isAuthenticated == true else {
            presentedAccountSetupContext = .restorePurchases
            return
        }
        Task {
            await billingService?.restorePurchases()
        }
    }
}

private struct ProUpsellHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meet Trai.")
                    .font(.traiBold(34))

                Text("Your goals. Actually happening.")
                    .font(.traiLabel(15))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(TraiColors.brandAccent.opacity(0.18))
                    .frame(width: 88, height: 88)
                    .blur(radius: 12)

                TraiLensView(size: 72, state: .thinking, palette: .energy)
            }
        }
    }
}

private struct ProUpsellBenefitList: View {
    let benefits: [ProUpsellBenefit]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(benefits, id: \.id) { benefit in
                ProUpsellBenefitRow(benefit: benefit)
            }
        }
        .frame(maxWidth: 420)
    }
}

private struct ProUpsellBenefitRow: View {
    let benefit: ProUpsellBenefit

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: benefit.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(TraiColors.brandAccent)
                .frame(width: 48, height: 48)
                .background(
                    TraiColors.brandAccent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.title)
                    .font(.traiHeadline(18))

                Text(benefit.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ProUpsellPurchaseCard: View {
    let product: SubscriptionProductDefinition
    let primaryButtonTitle: String
    let isPurchaseDisabled: Bool
    let isRestoreDisabled: Bool
    let errorMessage: String?
    let troubleshootingMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Trai Pro")
                        .font(.traiBold(30))

                    Text("\(product.priceDisplay) / month · Cancel anytime")
                        .font(.traiHeadline(15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Button(action: onPurchase) {
                        Text(primaryButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiPrimary(color: TraiColors.brandAccent, size: .large, fullWidth: true))
                    .disabled(isPurchaseDisabled)

                    Button(action: onRestore) {
                        Label("Restore purchase", systemImage: "arrow.trianglehead.counterclockwise")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoreDisabled)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let troubleshootingMessage {
                    Text(troubleshootingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

#Preview {
    ProUpsellView(source: .settings, showsDismissButton: false)
        .environment(BillingService.shared)
        .environment(MonetizationService.shared)
}
