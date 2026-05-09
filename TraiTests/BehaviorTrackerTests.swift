import XCTest
@testable import Trai

@MainActor
final class BehaviorTrackerTests: XCTestCase {
    func testSuggestionActionKeyMapsReviewAndPlanKeywords() {
        XCTAssertEqual(
            BehaviorTracker.suggestionActionKey(from: "Review workout plan"),
            BehaviorActionKey.reviewWorkoutPlan
        )
        XCTAssertEqual(
            BehaviorTracker.suggestionActionKey(from: "Review nutrition plan"),
            BehaviorActionKey.reviewNutritionPlan
        )
    }

    func testSuggestionActionKeyMapsCommonDomainKeywords() {
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Open profile"), BehaviorActionKey.openProfile)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Recovery check"), BehaviorActionKey.openRecovery)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Log weight"), BehaviorActionKey.logWeight)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Start training"), BehaviorActionKey.startWorkout)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Macros"), BehaviorActionKey.openMacroDetail)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Calorie target"), BehaviorActionKey.openCalorieDetail)
    }

    func testSuggestionActionKeyPrefersReminderWhenMultipleKeywordsMatch() {
        XCTAssertEqual(
            BehaviorTracker.suggestionActionKey(from: "Meal reminder"),
            BehaviorActionKey.completeReminder
        )
    }

    func testSuggestionActionKeyMapsMealFoodAndProteinToLogFood() {
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Log meal"), BehaviorActionKey.logFood)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Food check"), BehaviorActionKey.logFood)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "Protein goal"), BehaviorActionKey.logFood)
        XCTAssertEqual(BehaviorTracker.suggestionActionKey(from: "log_entry"), BehaviorActionKey.logFood)
    }

    func testSuggestionActionKeyFallsBackToNormalizedEngagementKey() {
        XCTAssertEqual(
            BehaviorTracker.suggestionActionKey(from: "Try New Habit"),
            "engagement.suggestion.try_new_habit"
        )
    }
}

@MainActor
final class FoodHealthKitSyncPolicyTests: XCTestCase {
    func testFoodSyncRequiresExplicitEnabledProfile() {
        XCTAssertFalse(FoodHealthKitSyncPolicy.shouldSyncFood(profile: nil))

        let profile = UserProfile()
        profile.syncFoodToHealthKit = false
        XCTAssertFalse(FoodHealthKitSyncPolicy.shouldSyncFood(profile: profile))

        profile.syncFoodToHealthKit = true
        XCTAssertTrue(FoodHealthKitSyncPolicy.shouldSyncFood(profile: profile))
    }

    func testFoodSyncUsesFirstProfileFromQueryResults() {
        let disabledProfile = UserProfile()
        disabledProfile.syncFoodToHealthKit = false

        let enabledProfile = UserProfile()
        enabledProfile.syncFoodToHealthKit = true

        XCTAssertFalse(FoodHealthKitSyncPolicy.shouldSyncFood(profiles: [disabledProfile, enabledProfile]))
        XCTAssertTrue(FoodHealthKitSyncPolicy.shouldSyncFood(profiles: [enabledProfile, disabledProfile]))
    }
}

@MainActor
final class AccountSessionTokenPersistenceTests: XCTestCase {
    func testLegacyDefaultsSessionMigratesSecretsToTokenStore() throws {
        let suiteName = "AccountSessionTokenPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let tokenStore = InMemorySessionTokenStore()
        let legacySnapshot = BackendSessionSnapshot(
            userID: "usr_test",
            identityProvider: .apple,
            email: "user@example.com",
            displayName: "User",
            accessToken: "access-secret",
            refreshToken: "refresh-secret",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastAuthenticatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        defaults.set(try JSONEncoder().encode(legacySnapshot), forKey: "account.backendSessionSnapshot.v1")

        let migrated = AccountSessionService.loadPersistedSessionSnapshot(defaults: defaults, tokenStore: tokenStore)
        AccountSessionService.persistSessionSnapshot(
            migrated.snapshot,
            authState: .authenticated,
            defaults: defaults,
            tokenStore: tokenStore
        )

        XCTAssertEqual(migrated.snapshot?.accessToken, "access-secret")
        XCTAssertTrue(migrated.needsRewrite)
        XCTAssertEqual(tokenStore.loadTokens(for: "usr_test")?.refreshToken, "refresh-secret")
        let persistedData = try XCTUnwrap(defaults.data(forKey: "account.backendSessionSnapshot.v1"))
        let persistedString = String(data: persistedData, encoding: .utf8) ?? ""
        XCTAssertFalse(persistedString.contains("access-secret"))
        XCTAssertFalse(persistedString.contains("refresh-secret"))
    }
}

private final class InMemorySessionTokenStore: SessionTokenStoring {
    private var tokensByUserID: [String: BackendSessionTokens] = [:]

    func loadTokens(for userID: String) -> BackendSessionTokens? {
        tokensByUserID[userID]
    }

    func saveTokens(_ tokens: BackendSessionTokens, for userID: String) {
        tokensByUserID[userID] = tokens
    }

    func deleteTokens(for userID: String) {
        tokensByUserID.removeValue(forKey: userID)
    }
}
