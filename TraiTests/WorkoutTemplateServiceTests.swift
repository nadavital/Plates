import XCTest
import SwiftData
@testable import Trai

@MainActor
final class WorkoutTemplateServiceTests: XCTestCase {
    private var service: WorkoutTemplateService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = WorkoutTemplateService()
    }

    override func tearDownWithError() throws {
        service = nil
        try super.tearDownWithError()
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, ExerciseHistory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        return ModelContext(container)
    }

    func testCreateCustomWorkoutUsesProvidedValues() {
        let workout = service.createCustomWorkout(
            name: "Conditioning Circuit",
            type: .cardio,
            muscles: [.quads, .glutes]
        )

        XCTAssertEqual(workout.name, "Conditioning Circuit")
        XCTAssertEqual(workout.type, .cardio)
        XCTAssertEqual(workout.muscleGroups, [.quads, .glutes])
    }

    func testCreateStartWorkoutFromTemplateMapsMuscleGroups() {
        let template = WorkoutPlan.WorkoutTemplate(
            name: "Upper Push",
            targetMuscleGroups: ["chest", "triceps"],
            exercises: [],
            estimatedDurationMinutes: 45,
            order: 0
        )

        let workout = service.createStartWorkout(from: template)

        XCTAssertEqual(workout.name, "Upper Push")
        XCTAssertEqual(workout.type, .strength)
        XCTAssertEqual(workout.muscleGroups, [.chest, .triceps])
    }

    func testCreateWorkoutForIntentMatchesTemplateByCaseInsensitiveContains() throws {
        let context = try makeInMemoryContext()
        let profile = UserProfile()
        profile.workoutPlan = WorkoutPlan(
            splitType: .upperLower,
            daysPerWeek: 4,
            templates: [
                WorkoutPlan.WorkoutTemplate(
                    name: "Upper Body Strength",
                    targetMuscleGroups: ["chest", "back", "shoulders"],
                    exercises: [],
                    estimatedDurationMinutes: 60,
                    order: 0
                )
            ],
            rationale: "Test",
            guidelines: [],
            progressionStrategy: .defaultStrategy,
            warnings: nil
        )
        context.insert(profile)
        try context.save()

        let workout = service.createWorkoutForIntent(
            name: "upper body",
            modelContext: context
        )

        XCTAssertEqual(workout.name, "Upper Body Strength")
        XCTAssertEqual(workout.type, .strength)
        XCTAssertEqual(workout.muscleGroups, [.chest, .back, .shoulders])
    }

    func testCreateWorkoutForIntentFallsBackToCustomNamedWorkout() throws {
        let context = try makeInMemoryContext()
        let workout = service.createWorkoutForIntent(
            name: "Fight Camp",
            modelContext: context
        )

        XCTAssertEqual(workout.name, "Fight Camp")
        XCTAssertEqual(workout.type, .strength)
        XCTAssertEqual(workout.muscleGroups, [])
    }

    func testCreateWorkoutForIntentCustomCreatesDefaultWorkout() throws {
        let context = try makeInMemoryContext()
        let workout = service.createWorkoutForIntent(
            name: "custom",
            modelContext: context
        )

        XCTAssertEqual(workout.name, "Custom Workout")
        XCTAssertEqual(workout.type, .strength)
        XCTAssertEqual(workout.muscleGroups, [])
    }

    func testSuggestedSetDefaultsUsesExplicitAIWeightWhenProvided() throws {
        let context = try makeInMemoryContext()

        let defaults = service.suggestedSetDefaults(
            exerciseName: "Bench Press",
            requestedReps: 8,
            requestedWeightKg: 72.4,
            modelContext: context
        )

        XCTAssertEqual(defaults.reps, 8)
        XCTAssertEqual(defaults.weight.kg, 72.5)
    }

    func testSuggestedSetDefaultsFallsBackToProgressedHistoryWeight() throws {
        let context = try makeInMemoryContext()
        let history = ExerciseHistory()
        history.exerciseName = "Bench Press"
        history.performedAt = Date()
        history.bestSetWeightKg = 60
        history.bestSetWeightLbs = 132.5
        history.bestSetReps = 12
        history.totalSets = 3
        history.repPattern = "12,12,12"
        history.weightPattern = "60,60,60"
        context.insert(history)
        try context.save()

        let defaults = service.suggestedSetDefaults(
            exerciseName: "Bench Press",
            requestedReps: 10,
            requestedWeightKg: nil,
            progressionStrategy: .defaultStrategy,
            modelContext: context
        )

        XCTAssertEqual(defaults.reps, 12)
        XCTAssertEqual(defaults.weight.kg, 62.5)
    }
}

@MainActor
final class MuscleRecoveryServicePerformanceTests: XCTestCase {
    private var service: MuscleRecoveryService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = .shared
    }

    override func tearDownWithError() throws {
        service = nil
        try super.tearDownWithError()
    }

    func testRecoveryCacheHitBehaviorUsesFreshTTLWindow() {
        let now = Date()

        service.debugSeedRecoveryCacheForTests(generatedAt: now.addingTimeInterval(-45))
        XCTAssertTrue(service.debugShouldUseRecoveryCache(forceRefresh: false, now: now))
        XCTAssertFalse(service.debugShouldUseRecoveryCache(forceRefresh: true, now: now))

        service.debugSeedRecoveryCacheForTests(generatedAt: now.addingTimeInterval(-100))
        XCTAssertFalse(service.debugShouldUseRecoveryCache(forceRefresh: false, now: now))
    }

    func testExerciseLookupCacheExpiresWithinBoundedWindow() {
        let now = Date()

        service.debugSeedExerciseLookupCacheForTests(generatedAt: now.addingTimeInterval(-120))
        XCTAssertTrue(service.debugShouldUseExerciseLookupCache(now: now))

        service.debugSeedExerciseLookupCacheForTests(generatedAt: now.addingTimeInterval(-400))
        XCTAssertFalse(service.debugShouldUseExerciseLookupCache(now: now))
    }
}
