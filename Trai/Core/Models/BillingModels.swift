import Foundation

enum AppAccountIdentityMode: String, Codable, CaseIterable {
    case anonymousDevice
    case appStoreAccount
    case signInWithApple

    var displayName: String {
        switch self {
        case .anonymousDevice: "Anonymous Device"
        case .appStoreAccount: "App Store Account"
        case .signInWithApple: "Sign in with Apple"
        }
    }
}

enum BackendEnvironment: String, Codable, CaseIterable {
    case localPlaceholder
    case localDevelopment
    case staging
    case production

    var displayName: String {
        switch self {
        case .localPlaceholder: "Local Placeholder"
        case .localDevelopment: "Local Development"
        case .staging: "Staging"
        case .production: "Production"
        }
    }
}

enum BillingSyncState: String, Codable, CaseIterable {
    case localOnly
    case readyForStoreKit
    case syncedWithBackend

    var displayName: String {
        switch self {
        case .localOnly: "Local Only"
        case .readyForStoreKit: "Ready for StoreKit"
        case .syncedWithBackend: "Synced with Backend"
        }
    }
}

enum AIProviderOverride: String, Codable, CaseIterable, Identifiable {
    case automatic
    case gemini
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .gemini: "Gemini"
        case .openai: "OpenAI"
        }
    }
}

struct AppAccountSnapshot: Codable, Equatable {
    var installationID: String
    var appAccountToken: String
    var identityMode: AppAccountIdentityMode
    var backendEnvironment: BackendEnvironment
    var customBackendBaseURL: String?
    var lastSyncedAt: Date?
}

struct SubscriptionProductDefinition: Codable, Equatable, Identifiable {
    var id: String
    var plan: SubscriptionPlan
    var displayName: String
    var priceDisplay: String
    var billingPeriodLabel: String
    var monthlyAIUnits: Int?
    var isPrimaryOffer: Bool
    var marketingPoints: [String]

    var subtitleText: String {
        "\(priceDisplay) • \(billingPeriodLabel)"
    }
}

struct BillingSyncPayload: Codable, Equatable {
    var accountSnapshot: AppAccountSnapshot
    var entitlementSnapshot: EntitlementSnapshot
    var quotaSnapshot: AIQuotaSnapshot?
    var availableProducts: [SubscriptionProductDefinition]
    var syncState: BillingSyncState
    var syncedAt: Date
}
