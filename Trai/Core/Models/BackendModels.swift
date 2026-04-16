import Foundation

enum IdentityProvider: String, Codable, Equatable, CaseIterable {
    case anonymous
    case apple

    var displayName: String {
        switch self {
        case .anonymous: "Anonymous"
        case .apple: "Sign in with Apple"
        }
    }
}

enum AccountAuthState: String, Codable, Equatable, CaseIterable {
    case anonymous
    case authenticating
    case authenticated
    case refreshing
    case failed

    var displayName: String {
        switch self {
        case .anonymous: "Signed Out"
        case .authenticating: "Signing In"
        case .authenticated: "Signed In"
        case .refreshing: "Refreshing"
        case .failed: "Needs Attention"
        }
    }
}

struct BackendSessionSnapshot: Codable, Equatable {
    var userID: String
    var identityProvider: IdentityProvider
    var email: String?
    var displayName: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var lastAuthenticatedAt: Date
}

struct RefreshSessionRequest: Codable, Equatable {
    var refreshToken: String
    var appAccountToken: String
}

struct AppleIdentityExchangeRequest: Codable, Equatable {
    var installationID: String
    var appAccountToken: String
    var identityToken: String
    var authorizationCode: String
    var rawNonce: String?
    var appleUserID: String
    var email: String?
    var displayName: String?
}

struct BackendBootstrapResponse: Codable, Equatable {
    var session: BackendSessionSnapshot
    var billing: BillingSyncPayload
}

struct StoreKitEntitlementSyncRequest: Codable, Equatable {
    var signedTransactions: [String]
    var entitlements: [StoreKitEntitlementRecord]
}

struct StoreKitEntitlementRecord: Codable, Equatable, Identifiable {
    var id: UInt64 { transactionID }
    var productID: String
    var transactionID: UInt64
    var originalTransactionID: UInt64
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var isUpgraded: Bool
    var appAccountToken: String?
}

struct BackendAIProxyRequest: Codable, Equatable {
    var feature: String
    var model: String
    var action: String
    var requestBody: JSONValue
}

struct BackendAIProxyResponse: Codable, Equatable {
    var text: String
    var entitlementSnapshot: EntitlementSnapshot?
    var quotaSnapshot: AIQuotaSnapshot?
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    init(any value: Any) throws {
        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let dictionary as [String: Any]:
            self = .object(try dictionary.mapValues { try JSONValue(any: $0) })
        case let array as [Any]:
            self = .array(try array.map { try JSONValue(any: $0) })
        case _ as NSNull:
            self = .null
        default:
            throw NSError(domain: "JSONValue", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON type: \(type(of: value))"])
        }
    }
}
