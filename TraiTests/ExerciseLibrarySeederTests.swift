import SwiftData
import XCTest
@testable import Trai

@MainActor
final class ExerciseLibrarySeederTests: XCTestCase {
    func testEnsureDefaultsSeedsBroadExerciseLibraryOnce() throws {
        let container = try ModelContainer(
            for: Exercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let inserted = ExerciseLibrarySeeder.ensureDefaults(in: context)
        let secondPassInserted = ExerciseLibrarySeeder.ensureDefaults(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let names = Set(exercises.map(\.name))

        XCTAssertGreaterThan(inserted, 0)
        XCTAssertEqual(secondPassInserted, 0)
        XCTAssertTrue(names.contains("Bench Press"))
        XCTAssertTrue(names.contains("Running"))
        XCTAssertTrue(names.contains("Hip Mobility Flow"))
        XCTAssertTrue(names.contains("Bouldering"))
        XCTAssertEqual(exercises.filter { $0.name == "Running" }.count, 1)

        let running = try XCTUnwrap(exercises.first { $0.name == "Running" })
        XCTAssertEqual(running.exerciseCategory, .cardio)
        XCTAssertEqual(running.trackingFields, [.duration, .distance, .calories])
        XCTAssertTrue(running.targetTags.contains("Endurance"))

        let mobility = try XCTUnwrap(exercises.first { $0.name == "Hip Mobility Flow" })
        XCTAssertEqual(mobility.exerciseCategory, .mobility)
        XCTAssertEqual(mobility.trackingFields, [.duration, .notes])
        XCTAssertTrue(mobility.targetTags.contains("Hips"))
    }
}
