import Foundation

enum BackendClientError: LocalizedError {
    case environmentNotConfigured
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case encodingFailure

    var errorDescription: String? {
        switch self {
        case .environmentNotConfigured:
            "Backend environment is not configured yet."
        case .invalidResponse:
            "The backend returned an invalid response."
        case .unauthorized:
            "Your session is no longer valid. Please sign in again."
        case .serverError(let statusCode, let message):
            "Backend error \(statusCode): \(message)"
        case .encodingFailure:
            "Failed to encode the backend request."
        }
    }
}

final class TraiBackendClient {
    static let shared = TraiBackendClient()

    private enum InfoKey {
        static let stagingBaseURL = "TRAIBackendStagingBaseURL"
        static let productionBaseURL = "TRAIBackendProductionBaseURL"
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.encodeBackendDate(date))
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let stringValue = try? container.decode(String.self),
               let date = Self.decodeBackendDate(stringValue) {
                return date
            }

            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date string in backend response."
            )
        }
        self.decoder = decoder
    }

    func baseURL(for environment: BackendEnvironment, customBackendBaseURL: String? = nil) -> URL? {
        switch environment {
        case .localPlaceholder:
            return nil
        case .localDevelopment:
            if let customBackendBaseURL,
               !customBackendBaseURL.isEmpty,
               let url = URL(string: customBackendBaseURL) {
                return url
            }
            return URL(string: "http://127.0.0.1:8789")
        case .staging:
            return configuredURL(forInfoKey: InfoKey.stagingBaseURL, fallback: "https://staging-api.trai.app")
        case .production:
            return configuredURL(forInfoKey: InfoKey.productionBaseURL, fallback: "https://api.trai.app")
        }
    }

    func proxyURL(
        action: String,
        streaming: Bool,
        environment: BackendEnvironment,
        customBackendBaseURL: String? = nil
    ) throws -> URL {
        guard let baseURL = baseURL(for: environment, customBackendBaseURL: customBackendBaseURL) else {
            throw BackendClientError.environmentNotConfigured
        }

        let path = streaming ? "/v1/ai/stream" : "/v1/ai/generate"
        return baseURL.appending(path: path).appending(queryItems: [
            URLQueryItem(name: "action", value: action)
        ])
    }

    func exchangeAppleIdentity(
        _ requestBody: AppleIdentityExchangeRequest,
        environment: BackendEnvironment,
        customBackendBaseURL: String? = nil
    ) async throws -> BackendBootstrapResponse {
        try await send(
            path: "/v1/auth/apple/exchange",
            method: "POST",
            body: requestBody,
            environment: environment,
            customBackendBaseURL: customBackendBaseURL,
            accessToken: nil,
            appAccountToken: requestBody.appAccountToken
        )
    }

    func fetchBootstrap(
        session: BackendSessionSnapshot,
        accountSnapshot: AppAccountSnapshot
    ) async throws -> BackendBootstrapResponse {
        try await send(
            path: "/v1/account/bootstrap",
            method: "GET",
            body: Optional<String>.none,
            environment: accountSnapshot.backendEnvironment,
            customBackendBaseURL: accountSnapshot.customBackendBaseURL,
            accessToken: session.accessToken,
            appAccountToken: accountSnapshot.appAccountToken
        )
    }

    func refreshSession(
        refreshToken: String,
        accountSnapshot: AppAccountSnapshot
    ) async throws -> BackendBootstrapResponse {
        try await send(
            path: "/v1/auth/refresh",
            method: "POST",
            body: RefreshSessionRequest(
                refreshToken: refreshToken,
                appAccountToken: accountSnapshot.appAccountToken
            ),
            environment: accountSnapshot.backendEnvironment,
            customBackendBaseURL: accountSnapshot.customBackendBaseURL,
            accessToken: nil,
            appAccountToken: accountSnapshot.appAccountToken
        )
    }

    func syncStoreKitEntitlements(
        signedTransactions: [String],
        _ entitlements: [StoreKitEntitlementRecord],
        session: BackendSessionSnapshot,
        accountSnapshot: AppAccountSnapshot
    ) async throws -> BillingSyncPayload {
        try await send(
            path: "/v1/billing/sync-storekit",
            method: "POST",
            body: StoreKitEntitlementSyncRequest(
                signedTransactions: signedTransactions,
                entitlements: entitlements
            ),
            environment: accountSnapshot.backendEnvironment,
            customBackendBaseURL: accountSnapshot.customBackendBaseURL,
            accessToken: session.accessToken,
            appAccountToken: accountSnapshot.appAccountToken
        )
    }

    private func send<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        environment: BackendEnvironment,
        customBackendBaseURL: String? = nil,
        accessToken: String?,
        appAccountToken: String
    ) async throws -> T {
        guard let baseURL = baseURL(for: environment, customBackendBaseURL: customBackendBaseURL) else {
            throw BackendClientError.environmentNotConfigured
        }

        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appAccountToken, forHTTPHeaderField: "X-Trai-App-Account-Token")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            guard let data = try? encoder.encode(body) else {
                throw BackendClientError.encodingFailure
            }
            request.httpBody = data
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw BackendClientError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown backend error"
            throw BackendClientError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BackendClientError.invalidResponse
        }
    }

    private static func encodeBackendDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func configuredURL(forInfoKey key: String, fallback: String) -> URL? {
        if let configuredValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           let url = URL(string: configuredValue),
           !configuredValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }
        return URL(string: fallback)
    }

    private static func decodeBackendDate(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
