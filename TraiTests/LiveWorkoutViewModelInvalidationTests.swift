import Observation
import SwiftData
import XCTest
@testable import Trai

@MainActor
final class LiveWorkoutViewModelInvalidationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: LiveWorkout.self,
            LiveWorkoutEntry.self,
            ExerciseHistory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testRepEditDoesNotInvalidateEntryListObservation() {
        let (workout, entry) = makeWorkout(initialReps: 8)
        context.insert(workout)

        let viewModel = LiveWorkoutViewModel(workout: workout)
        let entryListInvalidationCount = InvalidationCounter()

        withObservationTracking {
            _ = viewModel.entries.count
        } onChange: {
            entryListInvalidationCount.increment()
        }

        viewModel.updateSet(at: 0, in: entry, reps: 9)

        XCTAssertEqual(entry.sets.first?.reps, 9)
        XCTAssertEqual(entryListInvalidationCount.value, 0)
    }

    func testRepEditAcrossZeroBoundaryStillUpdatesProgressMetrics() {
        let (workout, entry) = makeWorkout(initialReps: 0)
        context.insert(workout)

        let viewModel = LiveWorkoutViewModel(workout: workout)

        XCTAssertEqual(viewModel.completedSets, 0)

        viewModel.updateSet(at: 0, in: entry, reps: 9)

        XCTAssertEqual(viewModel.completedSets, 1)
    }

    func testGeneralActivityEntryDoesNotMakeWorkoutCompleteUntilMarkedComplete() {
        let workout = LiveWorkout(name: "Recovery Session", workoutType: .mobility)
        let entry = LiveWorkoutEntry(
            exerciseName: "Hip Mobility",
            orderIndex: 0,
            exerciseType: "flexibility"
        )
        entry.durationSeconds = 600
        entry.workout = workout
        workout.entries = [entry]
        context.insert(workout)

        let viewModel = LiveWorkoutViewModel(workout: workout)

        XCTAssertFalse(viewModel.isWorkoutComplete)

        viewModel.toggleGeneralEntryCompletion(for: entry)

        XCTAssertTrue(viewModel.isWorkoutComplete)
    }

    func testActivityScopedFrequencyGoalCountsCompletedMatchingEntries() {
        let workout = LiveWorkout(name: "Legs + Support", workoutType: .strength)
        workout.completedAt = Date()
        let strengthEntry = LiveWorkoutEntry(exerciseName: "Back Squat", orderIndex: 0)
        strengthEntry.addSet(LiveWorkoutEntry.SetData(reps: 8, weight: .zero, completed: true))
        let supportEntry = LiveWorkoutEntry(
            exerciseName: "Easy Bike",
            orderIndex: 1,
            exerciseType: "cardio"
        )
        supportEntry.activityKind = .cardio
        supportEntry.activityRole = .finisher
        supportEntry.durationSeconds = 600
        supportEntry.completedAt = Date()
        workout.entries = [strengthEntry, supportEntry]

        let unmatchedWorkout = LiveWorkout(name: "Push", workoutType: .strength)
        unmatchedWorkout.completedAt = Date()
        let unmatchedEntry = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
        unmatchedEntry.addSet(LiveWorkoutEntry.SetData(reps: 8, weight: .zero, completed: true))
        unmatchedWorkout.entries = [unmatchedEntry]

        let goal = WorkoutGoal(
            title: "Complete weekly support work",
            goalKind: .frequency,
            linkedWorkoutType: .strength,
            linkedActivityKind: .cardio,
            linkedActivityRole: .finisher,
            targetValue: 1,
            targetUnit: "entries",
            periodUnit: .week,
            periodCount: 1,
            successCriteria: "You complete one matching support entry this week."
        )

        let insight = WorkoutGoalProgressResolver.insights(
            goals: [goal],
            workouts: [workout, unmatchedWorkout],
            exerciseHistory: [],
            useLbs: false
        ).first

        XCTAssertEqual(insight?.currentValueText, "1")
        XCTAssertEqual(insight?.progressFraction, 1)
    }

    func testActivityKindGoalMatchesLegacyCardioEntryType() {
        let workout = LiveWorkout(name: "Conditioning", workoutType: .mixed)
        workout.completedAt = Date()
        let cardioEntry = LiveWorkoutEntry(
            exerciseName: "Bike",
            orderIndex: 0,
            exerciseType: "cardio"
        )
        cardioEntry.durationSeconds = 900
        cardioEntry.completedAt = Date()
        workout.entries = [cardioEntry]

        let goal = WorkoutGoal(
            title: "Do weekly cardio support",
            goalKind: .frequency,
            linkedWorkoutType: .mixed,
            linkedActivityKind: .cardio,
            targetValue: 1,
            targetUnit: "entries",
            periodUnit: .week,
            periodCount: 1,
            successCriteria: "You complete one cardio entry this week."
        )

        let insight = WorkoutGoalProgressResolver.insights(
            goals: [goal],
            workouts: [workout],
            exerciseHistory: [],
            useLbs: false
        ).first

        XCTAssertEqual(insight?.currentValueText, "1")
        XCTAssertEqual(insight?.progressFraction, 1)
    }

    func testMixedWorkoutSuggestionsIncludeRelevantNonStrengthExercises() throws {
        container = try ModelContainer(
            for: LiveWorkout.self,
            LiveWorkoutEntry.self,
            Exercise.self,
            ExerciseHistory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)

        let bench = Exercise(name: "Bench Press", category: .strength, muscleGroup: .chest)
        let run = Exercise(name: "Running", category: .cardio)
        let mobility = Exercise(name: "Hip Mobility Flow", category: .mobility)
        context.insert(bench)
        context.insert(run)
        context.insert(mobility)

        let workout = LiveWorkout(
            name: "Push + Cardio",
            workoutType: .mixed,
            targetMuscleGroups: [.chest],
            focusAreas: ["Push", "cardio"]
        )
        let viewModel = LiveWorkoutViewModel(workout: workout)
        viewModel.debugRebuildSuggestionPoolForTests(modelContext: context)

        XCTAssertTrue(viewModel.availableSuggestions.contains { $0.exerciseName == "Bench Press" })
        XCTAssertTrue(viewModel.availableSuggestions.contains { $0.exerciseName == "Running" && $0.category == .cardio })
        XCTAssertFalse(viewModel.availableSuggestions.contains { $0.exerciseName == "Hip Mobility Flow" })
    }

    func testAddingCardioSuggestionCreatesTrackableCardioEntryWithoutPrefilledStrengthSets() {
        let workout = LiveWorkout(name: "Support", workoutType: .mixed)
        let viewModel = LiveWorkoutViewModel(workout: workout)
        let suggestion = LiveWorkoutViewModel.ExerciseSuggestion(
            exerciseName: "Running",
            muscleGroup: "Cardio",
            category: .cardio,
            targetTags: ["Endurance"],
            trackingFields: [.duration, .distance],
            defaultSets: 3,
            defaultReps: 10
        )

        viewModel.addExerciseFromSuggestion(suggestion)

        let entry = viewModel.entries.first
        XCTAssertEqual(entry?.exerciseName, "Running")
        XCTAssertEqual(entry?.exerciseType, "cardio")
        XCTAssertTrue(entry?.sets.isEmpty == true)
        XCTAssertEqual(entry?.targetTags, ["Endurance"])
        XCTAssertEqual(entry?.trackingFields, [.duration, .distance])
    }

    private func makeWorkout(initialReps: Int) -> (LiveWorkout, LiveWorkoutEntry) {
        let workout = LiveWorkout(name: "Push Day", workoutType: .strength)
        let entry = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: initialReps,
            weight: CleanWeight(kg: 80, lbs: 176.5),
            completed: false,
            isWarmup: false
        ))
        entry.workout = workout
        workout.entries = [entry]
        return (workout, entry)
    }
}

private final class InvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
