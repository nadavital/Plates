import XCTest
@testable import Trai

final class FoodMemoryMatcherTests: XCTestCase {
    private let matcher = FoodMemoryMatcher()

    func testAliasDriftStillMatchesSameMealStructure() {
        let memory = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 620,
            protein: 42,
            carbs: 58,
            fat: 16,
            components: [
                componentSummary("grilled chicken", role: .protein, calories: 242, protein: 38, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("white rice", role: .carb, calories: 206, protein: 4, carbs: 45, fat: 0, observationCount: 3)
            ],
            aliases: [
                FoodMemoryAlias(normalizedName: "chicken rice bowl", displayName: "Chicken Rice Bowl", observationCount: 2, wasUserEdited: false),
                FoodMemoryAlias(normalizedName: "grilled chicken bowl rice", displayName: "Grilled Chicken Bowl with Rice", observationCount: 1, wasUserEdited: true)
            ]
        )

        let snapshot = makeSnapshot(
            name: "Grilled Chicken Bowl with Rice",
            normalizedName: "grilled chicken bowl rice",
            calories: 628,
            protein: 43,
            carbs: 57,
            fat: 16,
            components: [
                component("grilled chicken", role: .protein, calories: 245, protein: 39, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 44, fat: 0)
            ]
        )

        let result = matcher.match(snapshot: snapshot, candidates: [memory])

        XCTAssertEqual(result.outcome, .matched)
        XCTAssertEqual(result.memoryId, memory.id)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.82)
    }

    func testNearMissMealWithDifferentDominantProteinCreatesCandidate() {
        let memory = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 620,
            protein: 42,
            carbs: 58,
            fat: 16,
            components: [
                componentSummary("grilled chicken", role: .protein, calories: 242, protein: 38, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("white rice", role: .carb, calories: 206, protein: 4, carbs: 45, fat: 0, observationCount: 3)
            ]
        )

        let snapshot = makeSnapshot(
            name: "Salmon Rice Bowl",
            normalizedName: "salmon rice bowl",
            calories: 675,
            protein: 36,
            carbs: 49,
            fat: 28,
            components: [
                component("salmon", role: .protein, calories: 320, protein: 32, carbs: 0, fat: 20),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        let result = matcher.match(snapshot: snapshot, candidates: [memory])

        XCTAssertEqual(result.outcome, .createCandidate)
        XCTAssertNil(result.memoryId)
        XCTAssertLessThan(result.confidence, 0.82)
    }

    func testSimpleNameTokenOverlapAloneDoesNotForceMatch() {
        let memory = makeMemory(
            displayName: "Turkey Sandwich",
            normalizedName: "turkey sandwich",
            calories: 430,
            protein: 28,
            carbs: 36,
            fat: 18,
            components: [
                componentSummary("turkey", role: .protein, calories: 120, protein: 22, carbs: 0, fat: 2, observationCount: 3),
                componentSummary("bread", role: .carb, calories: 160, protein: 6, carbs: 30, fat: 2, observationCount: 3)
            ]
        )

        let snapshot = makeSnapshot(
            name: "Turkey Salad",
            normalizedName: "turkey salad",
            calories: 310,
            protein: 29,
            carbs: 11,
            fat: 16,
            components: [
                component("turkey", role: .protein, calories: 130, protein: 24, carbs: 0, fat: 2),
                component("greens", role: .vegetable, calories: 25, protein: 2, carbs: 5, fat: 0),
                component("dressing", role: .sauce, calories: 90, protein: 0, carbs: 4, fat: 9)
            ]
        )

        let result = matcher.match(snapshot: snapshot, candidates: [memory])

        XCTAssertEqual(result.outcome, .createCandidate)
        XCTAssertLessThan(result.confidence, 0.82)
    }

    func testIndexFindsCandidatesThroughAliasAndMacroFingerprints() {
        let memory = makeMemory(
            displayName: "Protein Oats Bowl",
            normalizedName: "protein oat bowl",
            calories: 410,
            protein: 32,
            carbs: 46,
            fat: 9,
            components: [
                componentSummary("oat", role: .carb, calories: 180, protein: 6, carbs: 32, fat: 4, observationCount: 4),
                componentSummary("whey protein", role: .protein, calories: 120, protein: 24, carbs: 3, fat: 1, observationCount: 4)
            ],
            aliases: [
                FoodMemoryAlias(normalizedName: "overnight protein oats", displayName: "Overnight Protein Oats", observationCount: 2, wasUserEdited: false)
            ]
        )
        memory.fingerprints.append(
            FoodMemoryFingerprint(
                version: 1,
                type: .coarseMacroBucket,
                value: "cal:400|p:30|c:50|f:10"
            )
        )

        let snapshot = makeSnapshot(
            name: "Overnight Oats Protein Bowl",
            normalizedName: "overnight oat protein bowl",
            calories: 405,
            protein: 31,
            carbs: 47,
            fat: 10,
            components: [
                component("oat", role: .carb, calories: 182, protein: 6, carbs: 33, fat: 4),
                component("whey protein", role: .protein, calories: 118, protein: 23, carbs: 3, fat: 1)
            ]
        )

        let candidates = FoodMemoryIndex(memories: [memory]).candidates(for: snapshot)

        XCTAssertEqual(candidates.map(\.id), [memory.id])
    }

    func testRepresentsSameHabitForDuplicateMemoriesWithDifferentNames() {
        let primary = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 620,
            protein: 42,
            carbs: 58,
            fat: 16,
            components: [
                componentSummary("grilled chicken", role: .protein, calories: 242, protein: 38, carbs: 0, fat: 5, observationCount: 4),
                componentSummary("white rice", role: .carb, calories: 206, protein: 4, carbs: 45, fat: 0, observationCount: 4)
            ]
        )
        primary.aliases.append(
            FoodMemoryAlias(
                normalizedName: "grilled chicken bowl rice",
                displayName: "Grilled Chicken Bowl with Rice",
                observationCount: 1,
                wasUserEdited: true
            )
        )

        let duplicate = makeMemory(
            displayName: "Grilled Chicken Bowl with Rice",
            normalizedName: "grilled chicken bowl rice",
            calories: 626,
            protein: 43,
            carbs: 57,
            fat: 16,
            components: [
                componentSummary("grilled chicken", role: .protein, calories: 240, protein: 39, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("white rice", role: .carb, calories: 205, protein: 4, carbs: 44, fat: 0, observationCount: 3)
            ]
        )

        XCTAssertTrue(matcher.representsSameHabit(primary, duplicate))
        XCTAssertTrue(matcher.representsSameHabit(duplicate, primary))
    }

    func testMatchesEntryUsesStructuredAcceptedComponentsWithoutSnapshot() {
        let memory = makeMemory(
            displayName: "Morning Coffee",
            normalizedName: "morning coffee",
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [
                componentSummary("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0, observationCount: 4)
            ]
        )
        memory.kind = .food
        memory.fingerprints = [
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: "morning coffee"),
            FoodMemoryFingerprint(version: 1, type: .mealTimeBucket, value: MealTimeBucket.breakfast.rawValue)
        ]

        let entry = FoodEntry(
            name: "Cold Brew",
            mealType: FoodEntry.MealType.breakfast.rawValue,
            calories: 10,
            proteinGrams: 0,
            carbsGrams: 1,
            fatGrams: 0
        )
        entry.loggedAt = Date(timeIntervalSince1970: 1_714_000_000)
        entry.acceptedComponents = [
            component("coffee", role: .drink, calories: 10, protein: 0, carbs: 1, fat: 0)
        ]

        XCTAssertTrue(matcher.matches(entry: entry, memory: memory))
    }

    func testExactComponentEntryMatchRejectsIncompatibleMacros() {
        let memory = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 520,
            protein: 42,
            carbs: 55,
            fat: 12,
            components: [
                componentSummary("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0, observationCount: 3)
            ]
        )
        let entry = FoodRecommendationTestSupport.entry(
            name: "Family Size Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            calories: 1280,
            protein: 92,
            carbs: 150,
            fat: 36,
            components: [
                component("chicken", role: .protein, calories: 600, protein: 80, carbs: 0, fat: 20),
                component("rice", role: .carb, calories: 600, protein: 12, carbs: 140, fat: 3)
            ]
        )

        XCTAssertFalse(matcher.matches(entry: entry, memory: memory))
    }

    func testExactComponentEntryMatchAllowsCompatibleMacros() {
        let memory = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 620,
            protein: 42,
            carbs: 58,
            fat: 16,
            components: [
                componentSummary("chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0, observationCount: 3)
            ]
        )
        let entry = FoodRecommendationTestSupport.entry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            calories: 640,
            protein: 44,
            carbs: 60,
            fat: 17,
            components: [
                component("chicken", role: .protein, calories: 250, protein: 40, carbs: 0, fat: 6),
                component("rice", role: .carb, calories: 210, protein: 4, carbs: 46, fat: 1)
            ]
        )

        XCTAssertTrue(matcher.matches(entry: entry, memory: memory))
    }

    func testExactComponentEntryMatchUsesCanonicalComponentAliases() {
        let memory = makeMemory(
            displayName: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            calories: 620,
            protein: 42,
            carbs: 58,
            fat: 16,
            components: [
                componentSummary("grilled chicken breast", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5, observationCount: 3),
                componentSummary("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0, observationCount: 3)
            ]
        )
        let entry = FoodRecommendationTestSupport.entry(
            name: "Chicken And Rice",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            calories: 625,
            protein: 43,
            carbs: 58,
            fat: 16,
            components: [
                component("roasted chicken breast", role: .protein, calories: 240, protein: 39, carbs: 0, fat: 5),
                component("brown rice", role: .carb, calories: 210, protein: 4, carbs: 45, fat: 1)
            ]
        )

        XCTAssertTrue(matcher.matches(entry: entry, memory: memory))
    }

    private func makeMemory(
        displayName: String,
        normalizedName: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        components: [FoodMemoryComponentSummary],
        aliases: [FoodMemoryAlias] = []
    ) -> FoodMemory {
        let memory = FoodMemory()
        memory.displayName = displayName
        memory.primaryNormalizedName = normalizedName
        memory.kind = .meal
        memory.status = .confirmed
        memory.observationCount = 3
        memory.confirmedReuseCount = 2
        memory.confidenceScore = 0.9
        memory.aliases = aliases.isEmpty ? [FoodMemoryAlias(normalizedName: normalizedName, displayName: displayName, observationCount: 3, wasUserEdited: false)] : aliases
        memory.components = components
        memory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: calories,
            medianProteinGrams: protein,
            medianCarbsGrams: carbs,
            medianFatGrams: fat,
            medianFiberGrams: 5,
            medianSugarGrams: 4,
            lowerCaloriesBound: calories - 20,
            upperCaloriesBound: calories + 20,
            lowerProteinBound: protein - 3,
            upperProteinBound: protein + 3
        )
        memory.servingProfile = FoodMemoryServingProfile(
            commonServingText: "1 bowl",
            commonQuantity: nil,
            commonUnit: nil,
            quantityVariance: 0
        )
        memory.fingerprints = [
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: normalizedName),
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: normalizedName.split(separator: " ").sorted().joined(separator: " ")),
            FoodMemoryFingerprint(version: 1, type: .mealTimeBucket, value: MealTimeBucket.lunch.rawValue)
        ]
        memory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0.2,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 3,
            repeatedTimeBucketScore: 0.9
        )
        return memory
    }

    private func makeSnapshot(
        name: String,
        normalizedName: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        components: [AcceptedFoodComponent]
    ) -> AcceptedFoodSnapshot {
        AcceptedFoodSnapshot(
            version: 1,
            source: .camera,
            kind: .meal,
            displayName: name,
            normalizedDisplayName: normalizedName,
            nameAliases: [normalizedName, normalizedName.split(separator: " ").sorted().joined(separator: " ")],
            mealLabel: "lunch",
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: calories,
            totalProteinGrams: protein,
            totalCarbsGrams: carbs,
            totalFatGrams: fat,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: components,
            notes: nil,
            confidence: .high,
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            mealTimeBucket: .lunch,
            weekdayBucket: 3,
            userEditedFields: [],
            wasUserEdited: false
        )
    }

    private func component(
        _ normalizedName: String,
        role: FoodComponentRole,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> AcceptedFoodComponent {
        AcceptedFoodComponent(
            id: normalizedName,
            displayName: normalizedName.capitalized,
            normalizedName: normalizedName,
            role: role,
            quantity: nil,
            unit: nil,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: nil,
            sugarGrams: nil,
            preparation: nil,
            confidence: .high,
            source: .ai
        )
    }

    private func componentSummary(
        _ normalizedName: String,
        role: FoodComponentRole,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        observationCount: Int
    ) -> FoodMemoryComponentSummary {
        FoodMemoryComponentSummary(
            normalizedName: normalizedName,
            role: role,
            observationCount: observationCount,
            typicalCalories: calories,
            typicalProteinGrams: protein,
            typicalCarbsGrams: carbs,
            typicalFatGrams: fat
        )
    }
}
