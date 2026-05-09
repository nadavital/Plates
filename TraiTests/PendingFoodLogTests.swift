import XCTest
@testable import Trai

final class PendingFoodLogTests: XCTestCase {
    func testLegacyPendingFoodLogDecodesWithStableID() throws {
        let legacyJSON = """
        [
          {
            "name": "Black Coffee",
            "calories": 5,
            "protein": 0,
            "loggedAt": 788918400,
            "mealType": "drink"
          }
        ]
        """.data(using: .utf8)!

        let firstDecode = try JSONDecoder().decode([PendingFoodLog].self, from: legacyJSON)
        let secondDecode = try JSONDecoder().decode([PendingFoodLog].self, from: legacyJSON)

        XCTAssertEqual(firstDecode.first?.id, secondDecode.first?.id)
        XCTAssertEqual(firstDecode.first?.name, "Black Coffee")
        XCTAssertEqual(firstDecode.first?.mealType, "drink")
    }

    func testPendingFoodLogQueueRemovesOnlyProcessedIDs() throws {
        let suiteName = "PendingFoodLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = PendingFoodLog(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "Glass of Water",
            calories: 0,
            protein: 0,
            loggedAt: Date(timeIntervalSinceReferenceDate: 10),
            mealType: "drink"
        )
        let second = PendingFoodLog(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Quick Snack",
            calories: 150,
            protein: 5,
            loggedAt: Date(timeIntervalSinceReferenceDate: 20),
            mealType: "snack"
        )

        try PendingFoodLogQueue.save([first, second], to: defaults)
        try PendingFoodLogQueue.remove(ids: [first.id], from: defaults)

        XCTAssertEqual(PendingFoodLogQueue.load(from: defaults), [second])

        try PendingFoodLogQueue.remove(ids: [second.id], from: defaults)

        XCTAssertTrue(PendingFoodLogQueue.load(from: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs))
    }

    func testPendingFoodLogQueueIgnoresDuplicateIDs() throws {
        let suiteName = "PendingFoodLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let log = PendingFoodLog(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            name: "Black Coffee",
            calories: 5,
            protein: 0,
            loggedAt: Date(timeIntervalSinceReferenceDate: 30),
            mealType: "drink"
        )

        try PendingFoodLogQueue.append(log, to: defaults)
        try PendingFoodLogQueue.append(log, to: defaults)

        XCTAssertEqual(PendingFoodLogQueue.load(from: defaults), [log])
    }
}
