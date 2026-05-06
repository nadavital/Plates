import XCTest
@testable import Trai

@MainActor
final class FoodRecommendationEvaluatorTests: XCTestCase {
    func testReplayEvaluatorHidesFutureObservations() async throws {
        let entries = (0..<5).map { index in
            FoodRecommendationTestSupport.entry(
                name: "Chicken Rice Bowl \(index)",
                loggedAt: FoodRecommendationTestSupport.day(index),
                components: chickenRiceComponents()
            )
        }
        let observations = FoodObservationBuilder().observations(from: entries)
        var capturedTrainingDates: [[Date]] = []

        _ = try await FoodRecommendationReplayRunner().evaluate(
            observations: observations,
            entries: entries,
            memories: [],
            provider: { trainingEntries, _, _, _, _, _ in
                capturedTrainingDates.append(trainingEntries.map(\.loggedAt))
                return []
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 2)
        )

        XCTAssertFalse(capturedTrainingDates.isEmpty)
        for dates in capturedTrainingDates {
            let latestTrainingDay = dates.map { Calendar.current.startOfDay(for: $0) }.max()
            let hiddenDay = Calendar.current.startOfDay(for: entries[dates.count].loggedAt)
            XCTAssertLessThan(latestTrainingDay!, hiddenDay)
        }
    }

    func testReplayEvaluatorCountsCanonicalComponentHit() async throws {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Grilled Chicken With Rice", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenRiceComponents())
        ]
        let observations = FoodObservationBuilder().observations(from: entries)
        let result = try await FoodRecommendationReplayRunner().evaluate(
            observations: observations,
            entries: entries,
            memories: [],
            provider: { _, _, _, _, _, _ in
                [FoodRecommendationTestSupport.suggestion(name: "Chicken Rice Bowl", components: self.chickenRiceComponents())]
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 1)
        )

        XCTAssertEqual(result.metrics.hitAt1, 1)
    }

    func testReplayEvaluatorRejectsOneOffFalsePositive() async throws {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Grilled Chicken With Rice", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenRiceComponents())
        ]
        let result = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, _, _, _, _ in
                [FoodRecommendationTestSupport.suggestion(name: "Katz Pastrami Sandwich", calories: 850, protein: 35, carbs: 75, fat: 38, components: self.pastramiComponents())]
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 1)
        )

        XCTAssertEqual(result.metrics.hitAt1, 0)
        XCTAssertGreaterThan(result.metrics.oneOffFalsePositiveRate, 0)
    }

    func testReplayMetricsIncludeUsefulnessDiagnostics() async throws {
        let entries = [
            FoodRecommendationTestSupport.entry(name: "Chicken Rice Bowl", loggedAt: FoodRecommendationTestSupport.day(0), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Chicken Rice", loggedAt: FoodRecommendationTestSupport.day(1), components: chickenRiceComponents()),
            FoodRecommendationTestSupport.entry(name: "Grilled Chicken With Rice", loggedAt: FoodRecommendationTestSupport.day(2), components: chickenRiceComponents())
        ]
        let latte = FoodRecommendationTestSupport.component("latte", role: .drink, calories: 160, protein: 8, carbs: 14, fat: 6)
        let result = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, _, _, _, _ in
                [
                    FoodRecommendationTestSupport.suggestion(name: "Latte", calories: 160, protein: 8, carbs: 14, fat: 6, components: [latte]),
                    FoodRecommendationTestSupport.suggestion(name: "Cappuccino", calories: 110, protein: 6, carbs: 9, fat: 4, components: [latte])
                ]
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 1)
        )

        XCTAssertGreaterThan(result.metrics.beverageDominationRate, 0)
        XCTAssertEqual(result.metrics.completeMealCoverageRate, 0)
    }

    func testSessionAwareReplayCanUseCurrentSessionPrefix() async throws {
        var entries = sessionPairEntries(previousSessionCount: 3)
        let targetSessionID = UUID()
        entries.append(
            FoodRecommendationTestSupport.entry(
                name: "Coffee",
                loggedAt: FoodRecommendationTestSupport.day(3, hour: 8),
                calories: 5,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [FoodRecommendationTestSupport.component("coffee", role: .drink, calories: 5, protein: 0, carbs: 1, fat: 0)],
                sessionID: targetSessionID,
                sessionOrder: 0
            )
        )
        entries.append(
            FoodRecommendationTestSupport.entry(
                name: "Bagel",
                loggedAt: FoodRecommendationTestSupport.day(3, hour: 8).addingTimeInterval(300),
                calories: 290,
                protein: 10,
                carbs: 56,
                fat: 2,
                components: [FoodRecommendationTestSupport.component("bagel", role: .carb, calories: 290, protein: 10, carbs: 56, fat: 2)],
                sessionID: targetSessionID,
                sessionOrder: 1
            )
        )

        let sessionAware = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, _, _, sessionID, currentSessionEntries in
                guard sessionID != nil, currentSessionEntries.contains(where: { $0.name == "Coffee" }) else { return [] }
                return [
                    FoodRecommendationTestSupport.suggestion(
                        name: "Bagel",
                        calories: 290,
                        protein: 10,
                        carbs: 56,
                        fat: 2,
                        components: [FoodRecommendationTestSupport.component("bagel", role: .carb, calories: 290, protein: 10, carbs: 56, fat: 2)]
                    )
                ]
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 7, maximumCases: 1, includeSessionContext: true)
        )

        let noSession = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, _, _, sessionID, currentSessionEntries in
                XCTAssertNil(sessionID)
                XCTAssertTrue(currentSessionEntries.isEmpty)
                return []
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 6, maximumCases: 1, includeSessionContext: false)
        )

        XCTAssertEqual(sessionAware.metrics.hitAt1, 1)
        XCTAssertEqual(noSession.metrics.hitAt1, 0)
    }

    func testSessionAwareReplayDoesNotLeakLaterSessionItemsIntoProviderTraining() async throws {
        var entries = sessionPairEntries(previousSessionCount: 3)
        let targetSessionID = UUID()
        entries.append(contentsOf: [
            FoodRecommendationTestSupport.entry(
                name: "Coffee",
                loggedAt: FoodRecommendationTestSupport.day(3, hour: 8),
                calories: 5,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [FoodRecommendationTestSupport.component("coffee", role: .drink, calories: 5, protein: 0, carbs: 1, fat: 0)],
                sessionID: targetSessionID,
                sessionOrder: 0
            ),
            FoodRecommendationTestSupport.entry(
                name: "Bagel",
                loggedAt: FoodRecommendationTestSupport.day(3, hour: 8).addingTimeInterval(300),
                calories: 290,
                protein: 10,
                carbs: 56,
                fat: 2,
                components: [FoodRecommendationTestSupport.component("bagel", role: .carb, calories: 290, protein: 10, carbs: 56, fat: 2)],
                sessionID: targetSessionID,
                sessionOrder: 1
            ),
            FoodRecommendationTestSupport.entry(
                name: "Cookie",
                loggedAt: FoodRecommendationTestSupport.day(3, hour: 8).addingTimeInterval(600),
                calories: 180,
                protein: 2,
                carbs: 24,
                fat: 8,
                components: [FoodRecommendationTestSupport.component("cookie", role: .carb, calories: 180, protein: 2, carbs: 24, fat: 8)],
                sessionID: targetSessionID,
                sessionOrder: 2
            )
        ])
        var capturedCases: [(trainingNames: [String], prefixNames: [String])] = []

        _ = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { trainingEntries, _, _, _, _, currentSessionEntries in
                capturedCases.append((trainingEntries.map(\.name), currentSessionEntries.map(\.name)))
                return []
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 7, maximumCases: 2, includeSessionContext: true)
        )

        let bagelReplayCase = try XCTUnwrap(capturedCases.first { $0.prefixNames == ["Coffee"] })
        XCTAssertTrue(bagelReplayCase.trainingNames.contains("Coffee"))
        XCTAssertFalse(bagelReplayCase.trainingNames.contains("Cookie"))
    }

    func testReplayCapUsesMostRecentEligibleCases() async throws {
        let entries = (0..<8).map { index in
            FoodRecommendationTestSupport.entry(
                name: "Entry \(index)",
                loggedAt: FoodRecommendationTestSupport.day(index),
                components: chickenRiceComponents()
            )
        }
        var hiddenDates: [Date] = []

        _ = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, now, _, _, _ in
                hiddenDates.append(now)
                return []
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 2, includeSessionContext: true)
        )

        XCTAssertEqual(hiddenDates, [
            FoodRecommendationTestSupport.day(6),
            FoodRecommendationTestSupport.day(7)
        ])
    }

    func testReplayWithoutSessionContextPassesNilSessionContext() async throws {
        let entries = sessionPairEntries(previousSessionCount: 2)
        var capturedSessionID: UUID?
        var capturedPrefixCounts: [Int] = []

        _ = try await FoodRecommendationReplayRunner().evaluate(
            observations: FoodObservationBuilder().observations(from: entries),
            entries: entries,
            memories: [],
            provider: { _, _, _, _, sessionID, currentSessionEntries in
                capturedSessionID = sessionID
                capturedPrefixCounts.append(currentSessionEntries.count)
                return []
            },
            config: FoodRecommendationReplayConfig(minimumTrainingObservations: 2, maximumCases: 1, includeSessionContext: false)
        )

        XCTAssertNil(capturedSessionID)
        XCTAssertEqual(capturedPrefixCounts, [0])
    }

    private func chickenRiceComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
            FoodRecommendationTestSupport.component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
    }

    private func pastramiComponents() -> [AcceptedFoodComponent] {
        [
            FoodRecommendationTestSupport.component("pastrami", role: .protein, calories: 420, protein: 30, carbs: 0, fat: 30),
            FoodRecommendationTestSupport.component("rye bread", role: .carb, calories: 220, protein: 6, carbs: 40, fat: 3)
        ]
    }

    private func sessionPairEntries(previousSessionCount: Int) -> [FoodEntry] {
        var entries: [FoodEntry] = []
        for index in 0..<previousSessionCount {
            let sessionID = UUID()
            entries.append(
                FoodRecommendationTestSupport.entry(
                    name: "Coffee",
                    loggedAt: FoodRecommendationTestSupport.day(index, hour: 8),
                    calories: 5,
                    protein: 0,
                    carbs: 1,
                    fat: 0,
                    components: [FoodRecommendationTestSupport.component("coffee", role: .drink, calories: 5, protein: 0, carbs: 1, fat: 0)],
                    sessionID: sessionID,
                    sessionOrder: 0
                )
            )
            entries.append(
                FoodRecommendationTestSupport.entry(
                    name: "Bagel",
                    loggedAt: FoodRecommendationTestSupport.day(index, hour: 8).addingTimeInterval(300),
                    calories: 290,
                    protein: 10,
                    carbs: 56,
                    fat: 2,
                    components: [FoodRecommendationTestSupport.component("bagel", role: .carb, calories: 290, protein: 10, carbs: 56, fat: 2)],
                    sessionID: sessionID,
                    sessionOrder: 1
                )
            )
        }
        return entries
    }
}
