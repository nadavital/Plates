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
        var entryListInvalidationCount = 0

        withObservationTracking {
            _ = viewModel.entries.count
        } onChange: {
            entryListInvalidationCount += 1
        }

        viewModel.updateSet(at: 0, in: entry, reps: 9)

        XCTAssertEqual(entry.sets.first?.reps, 9)
        XCTAssertEqual(entryListInvalidationCount, 0)
    }

    func testRepEditAcrossZeroBoundaryStillUpdatesProgressMetrics() {
        let (workout, entry) = makeWorkout(initialReps: 0)
        context.insert(workout)

        let viewModel = LiveWorkoutViewModel(workout: workout)

        XCTAssertEqual(viewModel.completedSets, 0)

        viewModel.updateSet(at: 0, in: entry, reps: 9)

        XCTAssertEqual(viewModel.completedSets, 1)
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
