import XCTest
@testable import Trai

@MainActor
final class OnboardingProAccessStateTests: XCTestCase {
    func testAccessRefreshStartsInCheckingState() {
        let state = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: false,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(state.kind, .checkingAccess)
        XCTAssertEqual(state.primaryPurchaseTitle, "Checking Pro Access...")
        XCTAssertTrue(state.isPurchaseDisabled)
        XCTAssertTrue(state.isRestoreDisabled)
    }

    func testExistingProAccessShowsActiveStateRegardlessOfAuthentication() {
        let state = OnboardingProAccessState(
            isAuthenticated: false,
            canAccessAIFeatures: true,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(state.kind, .proActive)
        XCTAssertEqual(state.primaryPurchaseTitle, "Trai Pro Active")
        XCTAssertTrue(state.isPurchaseDisabled)
        XCTAssertNil(state.troubleshootingMessage)
    }

    func testProductLoadingDisablesPurchaseButKeepsRestoreAvailable() {
        let state = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: true,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(state.kind, .loadingProducts)
        XCTAssertEqual(state.primaryPurchaseTitle, "Unlock Trai Pro")
        XCTAssertTrue(state.isPurchaseDisabled)
        XCTAssertFalse(state.isRestoreDisabled)
    }

    func testAnonymousFreeUserIsPromptedToSignInBeforePurchase() {
        let state = OnboardingProAccessState(
            isAuthenticated: false,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(state.kind, .signInToAttachPro)
        XCTAssertEqual(state.primaryPurchaseTitle, "Sign in to unlock Trai Pro")
        XCTAssertFalse(state.isPurchaseDisabled)
        XCTAssertNil(state.troubleshootingMessage)
    }

    func testSignedInFreeUserCanUpgradeAfterRefresh() {
        let state = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(state.kind, .upgradeAvailable)
        XCTAssertEqual(state.primaryPurchaseTitle, "Unlock Trai Pro")
        XCTAssertFalse(state.isPurchaseDisabled)
        XCTAssertNil(state.troubleshootingMessage)
    }

    func testPurchaseAndRestoreStatesDisablePurchase() {
        let purchasing = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: "trai.pro.monthly",
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )
        let restoring = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: true,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: nil
        )

        XCTAssertEqual(purchasing.kind, .purchaseInFlight)
        XCTAssertEqual(purchasing.primaryPurchaseTitle, "Unlocking Trai Pro...")
        XCTAssertTrue(purchasing.isPurchaseDisabled)
        XCTAssertEqual(restoring.kind, .restoreInFlight)
        XCTAssertTrue(restoring.isPurchaseDisabled)
    }

    func testRefreshFailureKeepsStandardFallbackAvailable() {
        let state = OnboardingProAccessState(
            isAuthenticated: true,
            canAccessAIFeatures: false,
            didAttemptRefresh: true,
            isLoadingProducts: false,
            isRestoringPurchases: false,
            purchaseInFlightProductID: nil,
            recommendedProductID: "trai.pro.monthly",
            accessErrorMessage: "StoreKit unavailable"
        )

        XCTAssertEqual(state.kind, .accessUnavailable)
        XCTAssertEqual(state.primaryPurchaseTitle, "Unlock Trai Pro")
        XCTAssertEqual(state.statusMessage, "StoreKit unavailable")
        XCTAssertFalse(state.isPurchaseDisabled)
    }
}
