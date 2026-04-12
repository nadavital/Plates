//
//  PlanGenerationChoiceSheet.swift
//  Trai
//

import SwiftUI

struct PlanGenerationChoiceSheet: View {
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(BillingService.self) private var billingService: BillingService?

    let onContinueStandard: () -> Void

    @State private var hasRequestedProducts = false
    @State private var presentedAccountSetupContext: AccountSetupContext?

    private let source: ProUpsellSource = .nutritionPlan

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
        if accountSessionService?.isAuthenticated != true {
            return "Sign in to unlock Trai Pro"
        }
        if let billingService, billingService.purchaseInFlightProductID == product.id {
            return "Unlocking Trai Pro..."
        }
        return "Unlock Trai Pro"
    }

    private var isPurchaseDisabled: Bool {
        if accountSessionService?.isAuthenticated != true {
            return false
        }
        guard let billingService else { return true }
        return billingService.isLoadingProducts
            || billingService.isRestoringPurchases
            || billingService.purchaseInFlightProductID != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                onboardingHero

                ProUpsellBenefitList(benefits: source.benefits)

                ProUpsellPurchaseCard(
                    product: product,
                    primaryButtonTitle: primaryButtonTitle,
                    isPurchaseDisabled: isPurchaseDisabled,
                    isRestoreDisabled: billingService?.isRestoringPurchases == true,
                    errorMessage: billingService?.storeKitUpsellMessage,
                    troubleshootingMessage: accountSessionService?.isAuthenticated == true
                        ? nil
                        : "We’ll prompt Sign in with Apple first so your Trai Pro access is attached to your account.",
                    onPurchase: handlePurchase,
                    onRestore: handleRestore
                )

                standardPlanCard
            }
            .padding(20)
        }
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

    private var onboardingHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose how Trai builds your plan")
                        .font(.traiBold(30))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Start with a solid standard plan now, or unlock Trai Pro so Trai can build and refine it with you from day one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var standardPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start with the standard plan", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)

            Text("Trai will still build your first nutrition targets from your profile, and you can unlock Trai coaching later whenever you want deeper refinements.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onContinueStandard) {
                Text("Continue with Standard Plan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true, fillOpacity: 0.12))
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    PlanGenerationChoiceSheet(
        onContinueStandard: {}
    )
}
