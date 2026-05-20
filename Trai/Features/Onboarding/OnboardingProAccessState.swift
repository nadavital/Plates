//
//  OnboardingProAccessState.swift
//  Trai
//
//  Pure presentation state for onboarding Pro access and purchase choices.
//

import Foundation

struct OnboardingProAccessState: Equatable {
    enum Kind: Equatable {
        case checkingAccess
        case proActive
        case signInToAttachPro
        case upgradeAvailable
        case loadingProducts
        case purchaseInFlight
        case restoreInFlight
        case accessUnavailable
    }

    let isAuthenticated: Bool
    let canAccessAIFeatures: Bool
    let didAttemptRefresh: Bool
    let isLoadingProducts: Bool
    let isRestoringPurchases: Bool
    let purchaseInFlightProductID: String?
    let recommendedProductID: String
    let accessErrorMessage: String?

    var kind: Kind {
        if canAccessAIFeatures {
            return .proActive
        }
        if purchaseInFlightProductID == recommendedProductID {
            return .purchaseInFlight
        }
        if isRestoringPurchases {
            return .restoreInFlight
        }
        if isLoadingProducts {
            return .loadingProducts
        }
        if accessErrorMessage != nil {
            return .accessUnavailable
        }
        if !didAttemptRefresh {
            return .checkingAccess
        }
        if !isAuthenticated {
            return .signInToAttachPro
        }
        return .upgradeAvailable
    }

    var primaryPurchaseTitle: String {
        switch kind {
        case .checkingAccess:
            "Checking Pro Access..."
        case .proActive:
            "Trai Pro Active"
        case .signInToAttachPro:
            "Sign in to unlock Trai Pro"
        case .purchaseInFlight:
            "Unlocking Trai Pro..."
        case .restoreInFlight:
            "Restoring Purchases..."
        case .loadingProducts, .upgradeAvailable, .accessUnavailable:
            "Unlock Trai Pro"
        }
    }

    var isPurchaseDisabled: Bool {
        switch kind {
        case .checkingAccess, .proActive, .loadingProducts, .purchaseInFlight, .restoreInFlight:
            true
        case .signInToAttachPro, .upgradeAvailable, .accessUnavailable:
            false
        }
    }

    var isRestoreDisabled: Bool {
        switch kind {
        case .checkingAccess, .proActive, .restoreInFlight:
            true
        case .signInToAttachPro, .upgradeAvailable, .loadingProducts, .purchaseInFlight, .accessUnavailable:
            false
        }
    }

    var troubleshootingMessage: String? {
        nil
    }

    var statusMessage: String? {
        switch kind {
        case .checkingAccess:
            "Checking whether Trai Pro is already active."
        case .proActive:
            "Trai Pro is active. We’ll skip purchase prompts for included plan features."
        case .accessUnavailable:
            accessErrorMessage
        case .signInToAttachPro, .upgradeAvailable, .loadingProducts, .purchaseInFlight, .restoreInFlight:
            nil
        }
    }

    var signedInAccountMessage: String {
        switch kind {
        case .proActive:
            "Trai Pro is active on this account. We’ll skip purchase prompts for included plan features."
        case .checkingAccess:
            "We’re checking whether this account already has Trai Pro before showing plan choices."
        case .accessUnavailable:
            accessErrorMessage ?? "We couldn’t confirm Trai Pro yet. You can continue setup and restore or upgrade later."
        case .signInToAttachPro, .upgradeAvailable, .loadingProducts, .purchaseInFlight, .restoreInFlight:
            "We’ll use this account for subscriptions and Trai features."
        }
    }
}
