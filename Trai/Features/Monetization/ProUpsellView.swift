import SwiftUI

enum ProUpsellSource: String, Identifiable {
    case chat
    case foodAnalysis
    case nutritionPlan
    case workoutPlan
    case exerciseAnalysis
    case settings

    var id: String { rawValue }
}

struct ProUpsellView: View {
    private enum LegalURL {
        static let privacyPolicy = URL(string: "https://nadavavital.com/trai/privacy-policy")!
        static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    let source: ProUpsellSource
    var showsDismissButton = true
    var showsHeroCopy = true
    var dismissesWhenAccessGranted = true
    var headlineOverride: String?
    var taglineOverride: String?
    var modulesOverride: [ProUpsellModule]?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @State private var hasRequestedProducts = false
    @State private var presentedAccountSetupContext: AccountSetupContext?

    private var content: ProUpsellContent {
        source.offerContent
    }

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
        return "Continue with Trai Pro"
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
                TraiProGradientBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        proHero

                        TraiProValueList(modules: modulesOverride ?? content.modules)

                        purchaseSection

                        legalRow
                    }
                    .padding(.top, showsDismissButton ? 62 : 32)
                    .padding(.bottom, 28)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, 20)
                }

                if showsDismissButton {
                    Button("Dismiss", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.clear.tint(.black.opacity(0.16)).interactive(), in: .circle)
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
            guard hasAccess, dismissesWhenAccessGranted else { return }
            dismiss()
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
        .traiSheetBranding()
    }

    private var resolvedHeadline: String {
        headlineOverride ?? content.headline
    }

    private var resolvedTagline: String {
        taglineOverride ?? content.tagline
    }

    private var proHero: some View {
        VStack(spacing: 10) {
            TraiProWordmark()

            if showsHeroCopy {
                VStack(spacing: 4) {
                    Text(resolvedHeadline)
                        .font(.traiBold(28))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(resolvedTagline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.priceDisplay)
                    .font(.traiBold(30))
                    .foregroundStyle(.white)

                Text(product.billingPeriodLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))

                Spacer(minLength: 0)
            }

            Button(action: handlePurchase) {
                Text(primaryButtonTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TraiColors.brandAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white.opacity(0.92), in: .capsule)
                    .glassEffect(.clear.tint(.white.opacity(0.20)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isPurchaseDisabled)

            if let secondaryActionTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryActionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.16), in: .capsule)
                        .glassEffect(.clear.tint(.white.opacity(0.10)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            Text("Monthly auto-renewing subscription. Cancel anytime in App Store subscription settings.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = billingService?.storeKitUpsellMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var legalRow: some View {
        HStack(spacing: 12) {
            Button(action: handleRestore) {
                Text("Restore")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(billingService?.isRestoringPurchases == true)

            Spacer()

            Link("Terms", destination: LegalURL.termsOfUse)
            Link("Privacy", destination: LegalURL.privacyPolicy)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.76))
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

#Preview {
    ProUpsellView(source: .settings, showsDismissButton: false)
        .environment(BillingService.shared)
        .environment(MonetizationService.shared)
}
