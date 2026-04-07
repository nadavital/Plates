import Foundation

@MainActor @Observable
final class AppAccountService {
    static let shared = AppAccountService()

    private enum DefaultsKey {
        static let installationID = "account.installationID.v1"
        static let appAccountToken = "account.appAccountToken.v1"
        static let identityMode = "account.identityMode.v1"
        static let backendEnvironment = "account.backendEnvironment.v1"
        static let customBackendBaseURL = "account.customBackendBaseURL.v1"
        static let lastSyncedAt = "account.lastSyncedAt.v1"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var installationID: String
    private(set) var appAccountToken: String
    private(set) var identityMode: AppAccountIdentityMode
    private(set) var backendEnvironment: BackendEnvironment
    private(set) var customBackendBaseURL: String
    private(set) var lastSyncedAt: Date?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let resolvedInstallationID: String
        if let installationID = defaults.string(forKey: DefaultsKey.installationID),
           !installationID.isEmpty {
            resolvedInstallationID = installationID
        } else {
            let installationID = UUID().uuidString.lowercased()
            resolvedInstallationID = installationID
            defaults.set(installationID, forKey: DefaultsKey.installationID)
        }
        self.installationID = resolvedInstallationID

        if let storedToken = defaults.string(forKey: DefaultsKey.appAccountToken),
           !storedToken.isEmpty {
            self.appAccountToken = storedToken
        } else {
            let token = "trai_anon_\(resolvedInstallationID.prefix(12))"
            self.appAccountToken = token
            defaults.set(token, forKey: DefaultsKey.appAccountToken)
        }

        if let rawIdentity = defaults.string(forKey: DefaultsKey.identityMode),
           let identityMode = AppAccountIdentityMode(rawValue: rawIdentity) {
            self.identityMode = identityMode
        } else {
            self.identityMode = .anonymousDevice
        }

        if let rawBackendEnvironment = defaults.string(forKey: DefaultsKey.backendEnvironment),
           let backendEnvironment = BackendEnvironment(rawValue: rawBackendEnvironment) {
            self.backendEnvironment = backendEnvironment
        } else {
            #if DEBUG
            self.backendEnvironment = .localPlaceholder
            #else
            self.backendEnvironment = .production
            #endif
        }

        self.customBackendBaseURL = Self.normalizeCustomBackendBaseURL(
            defaults.string(forKey: DefaultsKey.customBackendBaseURL) ?? ""
        )
        self.lastSyncedAt = defaults.object(forKey: DefaultsKey.lastSyncedAt) as? Date
    }

    var shortAccountLabel: String {
        String(appAccountToken.prefix(18))
    }

    var backendStatusText: String {
        switch backendEnvironment {
        case .localPlaceholder:
            return "Backend not connected yet"
        case .localDevelopment:
            if !customBackendBaseURL.isEmpty {
                return "Connected to custom backend"
            }
            #if targetEnvironment(simulator)
            return "Connected to local backend"
            #else
            return "Local backend (simulator only)"
            #endif
        case .staging:
            return "Connected to staging"
        case .production:
            return "Connected to production"
        }
    }

    var realAccountSignInBlockedReason: String? {
        switch backendEnvironment {
        case .localPlaceholder:
            return "Choose a reachable backend before testing Sign in with Apple."
        case .localDevelopment:
            guard customBackendBaseURL.isEmpty else { return nil }
            guard !Self.supportsLocalDevelopmentBackendOnCurrentRuntime else { return nil }
            return "Local Development points at 127.0.0.1, so it only works in simulator-based testing. On this iPhone, use Production or enter a custom backend URL that points at your Mac or tunnel."
        case .staging, .production:
            return nil
        }
    }

    var recommendedBackendEnvironmentForRealAccountSignIn: BackendEnvironment? {
        switch backendEnvironment {
        case .localPlaceholder:
            return .production
        case .localDevelopment:
            if !customBackendBaseURL.isEmpty {
                return nil
            }
            return Self.supportsLocalDevelopmentBackendOnCurrentRuntime ? nil : .production
        case .staging, .production:
            return nil
        }
    }

    var currentSnapshot: AppAccountSnapshot {
        AppAccountSnapshot(
            installationID: installationID,
            appAccountToken: appAccountToken,
            identityMode: identityMode,
            backendEnvironment: backendEnvironment,
            customBackendBaseURL: customBackendBaseURL.nilIfEmpty,
            lastSyncedAt: lastSyncedAt
        )
    }

    func applyRemoteAccountSnapshot(_ snapshot: AppAccountSnapshot) {
        // Backend responses should update account identity metadata, but the app
        // remains the source of truth for which backend environment it should call.
        let localBackendEnvironment = backendEnvironment
        let localCustomBackendBaseURL = customBackendBaseURL
        installationID = snapshot.installationID
        appAccountToken = snapshot.appAccountToken
        identityMode = snapshot.identityMode
        backendEnvironment = localBackendEnvironment
        customBackendBaseURL = localCustomBackendBaseURL
        lastSyncedAt = snapshot.lastSyncedAt
        persist()
    }

    #if DEBUG
    func setDebugBackendEnvironment(_ environment: BackendEnvironment) {
        setBackendEnvironment(environment)
    }

    func setDebugIdentityMode(_ mode: AppAccountIdentityMode) {
        identityMode = mode
        persist()
    }
    #endif

    func setBackendEnvironment(_ environment: BackendEnvironment) {
        backendEnvironment = environment
        persist()
    }

    func setCustomBackendBaseURL(_ rawValue: String) {
        customBackendBaseURL = Self.normalizeCustomBackendBaseURL(rawValue)
        persist()
    }

    private func persist() {
        defaults.set(installationID, forKey: DefaultsKey.installationID)
        defaults.set(appAccountToken, forKey: DefaultsKey.appAccountToken)
        defaults.set(identityMode.rawValue, forKey: DefaultsKey.identityMode)
        defaults.set(backendEnvironment.rawValue, forKey: DefaultsKey.backendEnvironment)
        if customBackendBaseURL.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.customBackendBaseURL)
        } else {
            defaults.set(customBackendBaseURL, forKey: DefaultsKey.customBackendBaseURL)
        }
        defaults.set(lastSyncedAt, forKey: DefaultsKey.lastSyncedAt)
    }

    private static var supportsLocalDevelopmentBackendOnCurrentRuntime: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private static func normalizeCustomBackendBaseURL(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "" }
        guard let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            return trimmedValue
        }
        let normalizedPath = url.path == "/" ? "" : url.path
        var normalizedValue = "\(scheme)://\(host)"
        if let port = url.port {
            normalizedValue.append(":\(port)")
        }
        normalizedValue.append(normalizedPath)
        return normalizedValue
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
