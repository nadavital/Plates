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
