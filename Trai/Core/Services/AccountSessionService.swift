import AuthenticationServices
import CryptoKit
import Foundation

@MainActor @Observable
final class AccountSessionService {
    static let shared = AccountSessionService()

    private enum DefaultsKey {
        static let sessionSnapshot = "account.backendSessionSnapshot.v1"
        static let authState = "account.authState.v1"
        static let pendingAppleNonce = "account.pendingAppleNonce.v1"
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let encoder = JSONEncoder()
    @ObservationIgnored
    private let decoder = JSONDecoder()

    private let appAccountService: AppAccountService
    private let billingService: BillingService
    private let backendClient: TraiBackendClient
    private let tokenStore: SessionTokenStoring
    @ObservationIgnored
    private var pendingAppleNonce: String?
    @ObservationIgnored
    private var sessionOperationGeneration: UInt64 = 0

    private(set) var sessionSnapshot: BackendSessionSnapshot?
    private(set) var authState: AccountAuthState
    private(set) var isSyncingAccount = false
    private(set) var lastErrorMessage: String?

    init(
        defaults: UserDefaults = .standard,
        appAccountService: AppAccountService? = nil,
        billingService: BillingService? = nil,
        backendClient: TraiBackendClient? = nil,
        tokenStore: SessionTokenStoring? = nil
    ) {
        self.defaults = defaults
        self.appAccountService = appAccountService ?? .shared
        self.billingService = billingService ?? .shared
        self.backendClient = backendClient ?? .shared
        self.tokenStore = tokenStore ?? KeychainSessionTokenStore()

        let persistedSession = Self.loadPersistedSessionSnapshot(
            defaults: defaults,
            decoder: decoder,
            tokenStore: self.tokenStore
        )
        let initialSessionSnapshot = persistedSession.snapshot
        let needsSessionSnapshotRewrite = persistedSession.needsRewrite
        self.sessionSnapshot = initialSessionSnapshot

        if let rawValue = defaults.string(forKey: DefaultsKey.authState),
           let authState = AccountAuthState(rawValue: rawValue) {
            self.authState = authState
        } else {
            self.authState = initialSessionSnapshot == nil ? .anonymous : .authenticated
        }
        self.pendingAppleNonce = defaults.string(forKey: DefaultsKey.pendingAppleNonce)

        if needsSessionSnapshotRewrite {
            persist()
        }
    }

    var isAuthenticated: Bool {
        sessionSnapshot != nil && authState != .anonymous
    }

    var currentUserDisplayName: String {
        if let displayName = sessionSnapshot?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let email = sessionSnapshot?.email, !email.isEmpty {
            return email
        }
        return "Not signed in"
    }

    var sessionStatusText: String {
        let base = authState.displayName
        guard let expiresAt = sessionSnapshot?.expiresAt else { return base }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "\(base) • expires \(formatter.localizedString(for: expiresAt, relativeTo: Date()))"
    }

    var accessToken: String? {
        sessionSnapshot?.accessToken
    }

    var isSessionNearExpiry: Bool {
        guard let expiresAt = sessionSnapshot?.expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < (15 * 60)
    }

    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = Self.randomNonce()
        setPendingAppleNonce(rawNonce)
        lastErrorMessage = nil
        if sessionSnapshot == nil {
            authState = .anonymous
        }
        persist()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)
    }

    func handleAppleAuthorization(_ authorization: ASAuthorization) async {
        if let blockedReason = appAccountService.realAccountSignInBlockedReason {
            authState = .failed
            lastErrorMessage = blockedReason
            clearPendingAppleNonce()
            persist()
            return
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authState = .failed
            lastErrorMessage = "Apple sign-in returned an unexpected credential type."
            return
        }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            authState = .failed
            lastErrorMessage = "Apple sign-in did not return the required tokens."
            return
        }

        authState = .authenticating
        lastErrorMessage = nil
        let operationGeneration = sessionOperationGeneration

        do {
            guard let rawNonce = currentPendingAppleNonce() else {
                authState = .failed
                lastErrorMessage = "Apple sign-in session is missing its nonce. Please try again."
                return
            }

            let request = AppleIdentityExchangeRequest(
                installationID: appAccountService.installationID,
                appAccountToken: appAccountService.appAccountToken,
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                appleUserID: credential.user,
                email: credential.email,
                displayName: credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0).nilIfEmpty }
            )

            let bootstrap = try await backendClient.exchangeAppleIdentity(
                request,
                environment: appAccountService.backendEnvironment,
                customBackendBaseURL: appAccountService.currentSnapshot.customBackendBaseURL
            )

            guard canApplySessionOperation(generation: operationGeneration) else { return }
            applyAuthenticatedBootstrap(bootstrap)
            await billingService.reconcileAuthenticatedStoreKitPurchasesIfNeeded()

            var snapshot = appAccountService.currentSnapshot
            snapshot.identityMode = .signInWithApple
            snapshot.lastSyncedAt = Date()
            appAccountService.applyRemoteAccountSnapshot(snapshot)

            authState = .authenticated
            clearPendingAppleNonce()
            persist()
        } catch {
            authState = .failed
            lastErrorMessage = error.localizedDescription
            clearPendingAppleNonce()
            persist()
        }
    }

    func refreshAccountFromBackend() async {
        guard let sessionSnapshot else { return }
        guard !isSyncingAccount else { return }

        isSyncingAccount = true
        defer { isSyncingAccount = false }
        let operationGeneration = sessionOperationGeneration

        if isSessionNearExpiry, await refreshSessionIfNeeded() {
            guard canApplySessionOperation(generation: operationGeneration) else { return }
            isSyncingAccount = false
            await refreshAccountFromBackend()
            return
        }

        if self.sessionSnapshot?.expiresAt?.timeIntervalSinceNow ?? 60 > 0 {
            authState = .refreshing
        }

        do {
            let bootstrap = try await backendClient.fetchBootstrap(
                session: sessionSnapshot,
                accountSnapshot: appAccountService.currentSnapshot
            )

            guard canApplySessionOperation(
                generation: operationGeneration,
                matchingAccessToken: sessionSnapshot.accessToken
            ) else { return }
            applyAuthenticatedBootstrap(bootstrap)

            var snapshot = appAccountService.currentSnapshot
            snapshot.identityMode = bootstrap.session.identityProvider == .apple ? .signInWithApple : .anonymousDevice
            snapshot.lastSyncedAt = Date()
            appAccountService.applyRemoteAccountSnapshot(snapshot)

            authState = .authenticated
            lastErrorMessage = nil
            persist()
        } catch {
            if let backendError = error as? BackendClientError, case .unauthorized = backendError {
                if await refreshSessionIfNeeded() {
                    guard canApplySessionOperation(generation: operationGeneration) else { return }
                    isSyncingAccount = false
                    await refreshAccountFromBackend()
                    return
                }

                signOut()
                authState = .failed
                lastErrorMessage = backendError.localizedDescription
                persist()
                return
            }

            restoreSessionBackedAuthState(after: error)
        }
    }

    func refreshSessionIfNeeded() async -> Bool {
        guard let refreshToken = sessionSnapshot?.refreshToken else {
            return false
        }

        authState = .refreshing
        let operationGeneration = sessionOperationGeneration

        do {
            let bootstrap = try await backendClient.refreshSession(
                refreshToken: refreshToken,
                accountSnapshot: appAccountService.currentSnapshot
            )

            guard canApplySessionOperation(generation: operationGeneration) else {
                return false
            }
            applyAuthenticatedBootstrap(bootstrap)

            var snapshot = appAccountService.currentSnapshot
            snapshot.identityMode = bootstrap.session.identityProvider == .apple ? .signInWithApple : .anonymousDevice
            snapshot.lastSyncedAt = Date()
            appAccountService.applyRemoteAccountSnapshot(snapshot)

            authState = .authenticated
            lastErrorMessage = nil
            persist()
            return true
        } catch {
            restoreSessionBackedAuthState(after: error)
            return false
        }
    }

    func handleAuthorizationFailure(_ error: Error) {
        if Self.isUserCancelledAuthorization(error) {
            clearPendingAppleNonce()
            lastErrorMessage = nil
            authState = sessionSnapshot == nil ? .anonymous : .authenticated
            persist()
            return
        }

        authState = .failed
        lastErrorMessage = error.localizedDescription
        clearPendingAppleNonce()
        persist()
    }

    #if DEBUG
    func setDebugAuthenticatedSession(
        userID: String = "ui-test-user",
        displayName: String = "UI Test User"
    ) {
        sessionSnapshot = BackendSessionSnapshot(
            userID: userID,
            identityProvider: .anonymous,
            email: nil,
            displayName: displayName,
            accessToken: "ui-test-access-token",
            refreshToken: "ui-test-refresh-token",
            expiresAt: Date().addingTimeInterval(24 * 60 * 60),
            lastAuthenticatedAt: Date()
        )
        authState = .authenticated
        lastErrorMessage = nil
        clearPendingAppleNonce()
        persist()
    }
    #endif

    func signOut() {
        invalidatePendingSessionOperations()
        if let userID = sessionSnapshot?.userID {
            tokenStore.deleteTokens(for: userID)
        }
        sessionSnapshot = nil
        authState = .anonymous
        lastErrorMessage = nil
        if currentPendingAppleNonce() == nil {
            clearPendingAppleNonce()
        }

        var snapshot = appAccountService.currentSnapshot
        snapshot.identityMode = .anonymousDevice
        snapshot.lastSyncedAt = Date()
        appAccountService.applyRemoteAccountSnapshot(snapshot)

        billingService.handleSignedOutAccountState()
        persist()
    }

    func deleteAccount() async throws {
        guard let sessionSnapshot else {
            signOut()
            return
        }

        authState = .refreshing
        isSyncingAccount = true
        lastErrorMessage = nil
        defer { isSyncingAccount = false }

        do {
            _ = try await backendClient.deleteAccount(
                session: sessionSnapshot,
                accountSnapshot: appAccountService.currentSnapshot
            )
            signOut()
        } catch {
            restoreSessionBackedAuthState(after: error)
            throw error
        }
    }

    private func persist() {
        Self.persistSessionSnapshot(
            sessionSnapshot,
            authState: authState,
            defaults: defaults,
            encoder: encoder,
            tokenStore: tokenStore
        )
    }

    private func setPendingAppleNonce(_ nonce: String) {
        pendingAppleNonce = nonce
        defaults.set(nonce, forKey: DefaultsKey.pendingAppleNonce)
    }

    private func clearPendingAppleNonce() {
        pendingAppleNonce = nil
        defaults.removeObject(forKey: DefaultsKey.pendingAppleNonce)
    }

    private func currentPendingAppleNonce() -> String? {
        if let pendingAppleNonce, !pendingAppleNonce.isEmpty {
            return pendingAppleNonce
        }

        if let storedNonce = defaults.string(forKey: DefaultsKey.pendingAppleNonce),
           !storedNonce.isEmpty {
            pendingAppleNonce = storedNonce
            return storedNonce
        }

        return nil
    }

    private func restoreSessionBackedAuthState(after error: Error) {
        lastErrorMessage = error.localizedDescription
        authState = sessionSnapshot == nil ? .anonymous : .authenticated
        persist()
    }

    private func applyAuthenticatedBootstrap(_ bootstrap: BackendBootstrapResponse) {
        var resolvedSession = bootstrap.session
        if resolvedSession.refreshToken == nil,
           let existingSession = sessionSnapshot,
           existingSession.userID == resolvedSession.userID {
            resolvedSession.refreshToken = existingSession.refreshToken
        }
        if let existingSession = sessionSnapshot,
           existingSession.userID != resolvedSession.userID {
            tokenStore.deleteTokens(for: existingSession.userID)
        }
        sessionSnapshot = resolvedSession
        billingService.applyRemotePayload(bootstrap.billing)
    }

    private func invalidatePendingSessionOperations() {
        sessionOperationGeneration &+= 1
    }

    private func canApplySessionOperation(
        generation: UInt64,
        matchingAccessToken accessToken: String? = nil
    ) -> Bool {
        guard generation == sessionOperationGeneration else { return false }
        guard let accessToken else { return true }
        return sessionSnapshot?.accessToken == accessToken
    }

    static func loadPersistedSessionSnapshot(
        defaults: UserDefaults,
        decoder: JSONDecoder = JSONDecoder(),
        tokenStore: SessionTokenStoring
    ) -> (snapshot: BackendSessionSnapshot?, needsRewrite: Bool) {
        guard let data = defaults.data(forKey: DefaultsKey.sessionSnapshot) else {
            return (nil, false)
        }

        if let snapshot = try? decoder.decode(BackendSessionSnapshot.self, from: data) {
            tokenStore.saveTokens(
                BackendSessionTokens(accessToken: snapshot.accessToken, refreshToken: snapshot.refreshToken),
                for: snapshot.userID
            )
            return (snapshot, true)
        }

        if let metadata = try? decoder.decode(PersistedBackendSessionMetadata.self, from: data),
           let tokens = tokenStore.loadTokens(for: metadata.userID) {
            return (metadata.sessionSnapshot(applying: tokens), false)
        }

        return (nil, false)
    }

    static func persistSessionSnapshot(
        _ sessionSnapshot: BackendSessionSnapshot?,
        authState: AccountAuthState,
        defaults: UserDefaults,
        encoder: JSONEncoder = JSONEncoder(),
        tokenStore: SessionTokenStoring
    ) {
        defaults.set(authState.rawValue, forKey: DefaultsKey.authState)
        if let sessionSnapshot {
            tokenStore.saveTokens(
                BackendSessionTokens(
                    accessToken: sessionSnapshot.accessToken,
                    refreshToken: sessionSnapshot.refreshToken
                ),
                for: sessionSnapshot.userID
            )
        }

        if let sessionSnapshot,
           let data = try? encoder.encode(PersistedBackendSessionMetadata(sessionSnapshot)) {
            defaults.set(data, forKey: DefaultsKey.sessionSnapshot)
        } else {
            defaults.removeObject(forKey: DefaultsKey.sessionSnapshot)
        }
    }
}

private struct PersistedBackendSessionMetadata: Codable, Equatable {
    var userID: String
    var identityProvider: IdentityProvider
    var email: String?
    var displayName: String?
    var expiresAt: Date?
    var lastAuthenticatedAt: Date

    init(_ snapshot: BackendSessionSnapshot) {
        userID = snapshot.userID
        identityProvider = snapshot.identityProvider
        email = snapshot.email
        displayName = snapshot.displayName
        expiresAt = snapshot.expiresAt
        lastAuthenticatedAt = snapshot.lastAuthenticatedAt
    }

    func sessionSnapshot(applying tokens: BackendSessionTokens) -> BackendSessionSnapshot {
        BackendSessionSnapshot(
            userID: userID,
            identityProvider: identityProvider,
            email: email,
            displayName: displayName,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: expiresAt,
            lastAuthenticatedAt: lastAuthenticatedAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension AccountSessionService {
    static func randomNonce(length: Int = 32) -> String {
        (0..<length)
            .map { _ in UInt8.random(in: .min ... .max) }
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isUserCancelledAuthorization(_ error: Error) -> Bool {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }
}
