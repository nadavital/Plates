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
