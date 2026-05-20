//
//  PlanGenerationChoiceSheet.swift
//  Trai
//

import SwiftUI

struct PlanGenerationChoiceSheet: View {
    private enum LegalURL {
        static let privacyPolicy = URL(string: "https://nadavavital.com/trai/privacy-policy")!
        static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    let onContinueStandard: () -> Void

    @State private var hasRequestedProducts = false
    @State private var presentedAccountSetupContext: AccountSetupContext?

    private let content = ProUpsellSource.nutritionPlan.offerContent

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
                "AI-built nutrition targets",
                "Photo food logging",
                "Plan coaching as you log"
            ]
        )
    }

    private var primaryButtonTitle: String {
        switch proAccessState.kind {
        case .checkingAccess, .loadingProducts:
            "Preparing..."
        case .proActive:
            "Trai Pro Active"
        case .purchaseInFlight:
            "Unlocking..."
        case .restoreInFlight:
            "Restoring..."
        case .signInToAttachPro, .upgradeAvailable, .accessUnavailable:
            "Continue with Trai Pro"
        }
    }

    private var isPurchaseDisabled: Bool {
        proAccessState.isPurchaseDisabled
    }

    private var proAccessState: OnboardingProAccessState {
        OnboardingProAccessState(
            isAuthenticated: accountSessionService?.isAuthenticated == true,
            canAccessAIFeatures: monetizationService?.canAccessAIFeatures == true,
            didAttemptRefresh: hasRequestedProducts,
            isLoadingProducts: billingService?.isLoadingProducts == true,
            isRestoringPurchases: billingService?.isRestoringPurchases == true,
            purchaseInFlightProductID: billingService?.purchaseInFlightProductID,
            recommendedProductID: product.id,
            accessErrorMessage: billingService?.storeKitUpsellMessage
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                proOfferCard

                standardPlanButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(TraiProGradientBackground())
        .task {
            guard !hasRequestedProducts else { return }
            hasRequestedProducts = true
            await billingService?.refreshStoreKitProductsIfNeeded(force: false)
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
    }

    private var proOfferCard: some View {
        VStack(spacing: 20) {
            heroSection

            TraiProValueList(modules: content.modules)

            purchaseSection

            legalRow
        }
    }

    private var heroSection: some View {
        VStack(spacing: 10) {
            TraiProWordmark()

            VStack(spacing: 6) {
                Text(content.headline)
                    .font(.traiBold(28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(content.tagline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
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

            Text("Monthly auto-renewing subscription. Cancel anytime in App Store subscription settings.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let statusMessage {
                Text(statusMessage)
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
            .disabled(proAccessState.isRestoreDisabled)

            Spacer()

            Link("Terms", destination: LegalURL.termsOfUse)
            Link("Privacy", destination: LegalURL.privacyPolicy)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.76))
    }

    private var standardPlanButton: some View {
        Button(action: onContinueStandard) {
            Text("Continue without Pro")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.clear.tint(.white.opacity(0.16)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var statusMessage: String? {
        if let errorMessage = billingService?.storeKitUpsellMessage {
            return errorMessage
        }
        return nil
    }

    private func handlePurchase() {
        guard let billingService else { return }
        guard proAccessState.kind != .proActive else { return }
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
    PlanGenerationChoiceSheet(
        onContinueStandard: {}
    )
}
