import XCTest
import SwiftData
@testable import Trai

@MainActor
final class FoodMemoryModelStorageTests: XCTestCase {
    func testSettingAcceptedSnapshotOnFoodEntryDoesNotCrash() {
        let loggedAt = Date(timeIntervalSince1970: 1_714_000_000)
        let snapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .camera,
            kind: .meal,
            displayName: "Chicken Rice Bowl",
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            nameAliases: FoodNormalizationService().aliasCandidates(for: "Chicken Rice Bowl"),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: 620,
            totalProteinGrams: 42,
            totalCarbsGrams: 58,
            totalFatGrams: 16,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ],
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: .lunch,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )
        let rawData = try? JSONEncoder().encode(snapshot)

        XCTAssertNotNil(rawData)

        let entry = FoodEntry(
            name: "Chicken Rice Bowl",
            mealType: FoodEntry.MealType.lunch.rawValue,
            calories: 620,
            proteinGrams: 42,
            carbsGrams: 58,
            fatGrams: 16
        )
        entry.acceptedSnapshotData = rawData

        XCTAssertNotNil(entry.acceptedSnapshotData)
    }

    func testEncodingAcceptedSnapshotPayloadSucceedsOutsideModel() throws {
        let loggedAt = Date(timeIntervalSince1970: 1_714_000_000)
        let snapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .camera,
            kind: .meal,
            displayName: "Chicken Rice Bowl",
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            nameAliases: FoodNormalizationService().aliasCandidates(for: "Chicken Rice Bowl"),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: 620,
            totalProteinGrams: 42,
            totalCarbsGrams: 58,
            totalFatGrams: 16,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ],
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: .lunch,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )

        let rawData = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AcceptedFoodSnapshot.self, from: rawData)

        XCTAssertEqual(decoded.displayName, "Chicken Rice Bowl")
        XCTAssertEqual(decoded.components.count, 2)
    }

    func testSettingStructuredFieldsOnFoodMemoryDoesNotCrash() {
        let memory = FoodMemory()
        memory.kind = .meal
        memory.status = .candidate
        memory.displayName = "Chicken Rice Bowl"
        memory.primaryNormalizedName = "chicken rice bowl"
        memory.aliases = [
            FoodMemoryAlias(
                normalizedName: "chicken rice bowl",
                displayName: "Chicken Rice Bowl",
                observationCount: 1,
                wasUserEdited: false
            )
        ]
        memory.components = [
            FoodMemoryComponentSummary(
                normalizedName: "grilled chicken",
                role: .protein,
                observationCount: 1,
                typicalCalories: 240,
                typicalProteinGrams: 38,
                typicalCarbsGrams: 0,
                typicalFatGrams: 5
            )
        ]

        XCTAssertNotNil(memory.aliasesData)
        XCTAssertEqual(memory.aliases.count, 1)
        XCTAssertEqual(memory.components.count, 1)
    }

    func testPersistingFoodEntryWithAcceptedSnapshotInSingleModelContainerRoundTrips() throws {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.acceptedComponents.count, 2)
        XCTAssertEqual(entries.first?.acceptedSnapshot?.displayName, "Chicken Rice Bowl")
    }

    func testPersistingFoodMemoryInSingleModelContainerRoundTrips() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let memory = FoodMemory()
        memory.kind = .meal
        memory.status = .candidate
        memory.displayName = "Chicken Rice Bowl"
        memory.primaryNormalizedName = "chicken rice bowl"
        memory.aliases = [
            FoodMemoryAlias(
                normalizedName: "chicken rice bowl",
                displayName: "Chicken Rice Bowl",
                observationCount: 1,
                wasUserEdited: false
            )
        ]
        memory.components = [
            FoodMemoryComponentSummary(
                normalizedName: "grilled chicken",
                role: .protein,
                observationCount: 1,
                typicalCalories: 240,
                typicalProteinGrams: 38,
                typicalCarbsGrams: 0,
                typicalFatGrams: 5
            )
        ]

        context.insert(memory)
        try context.save()

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.aliases.count, 1)
        XCTAssertEqual(memories.first?.components.count, 1)
    }

    func testPersistingFullyPopulatedFoodMemoryInSingleModelContainerRoundTrips() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let memory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )

        context.insert(memory)
        try context.save()

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let storedMemory = try XCTUnwrap(memories.first)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(storedMemory.aliases.count, 1)
        XCTAssertEqual(storedMemory.components.count, 2)
        XCTAssertEqual(storedMemory.fingerprints.count, 5)
        XCTAssertEqual(storedMemory.representativeEntryIds.count, 1)
        XCTAssertEqual(storedMemory.matchStats?.lastResolverVersion, 1)
    }

    func testCreatingCombinedFoodEntryAndFoodMemoryContainerSucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])

        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )

        XCTAssertNotNil(container)
    }

    func testPersistingFullyPopulatedFoodMemoryInCombinedContainerAfterFetchingFoodEntryRoundTrips() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        context.insert(entry)

        let fetchedEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        let fetchedEntry = try XCTUnwrap(fetchedEntries.first)
        let snapshot = try XCTUnwrap(fetchedEntry.acceptedSnapshot)
        let memory = makeMemory(
            name: snapshot.displayName,
            normalizedName: snapshot.normalizedDisplayName,
            loggedAt: snapshot.loggedAt,
            entryID: fetchedEntry.id,
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )

        context.insert(memory)
        try context.save()

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.displayName, "Chicken Rice Bowl")
    }

    func testResolvingPendingEntriesInCombinedInMemoryContainerCreatesCandidate() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)
        let entryID = entry.id
        try service.resolvePendingEntries(limit: 5, modelContext: context)

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let refreshedEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        let refreshedEntry = try XCTUnwrap(refreshedEntries.first(where: { $0.id == entryID }))
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .createdCandidate)
    }

    func testCreatingCombinedFileBackedContainerSucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodMemoryModelStorageTests-\(UUID().uuidString).store")

        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        )

        XCTAssertNotNil(container)
    }

    func testUpdatingTrackedFoodEntryWithResolutionFieldsWithoutExplanationSucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        let memory = FoodMemory()
        memory.displayName = "Chicken Rice Bowl"
        memory.primaryNormalizedName = "chicken rice bowl"

        context.insert(entry)
        let entryID = entry.id
        context.insert(memory)

        entry.foodMemoryNeedsResolution = false
        entry.foodMemoryResolutionState = .createdCandidate
        entry.foodMemoryMatchConfidence = 0
        entry.foodMemoryMatchVersion = 1
        entry.foodMemoryResolvedAt = .now
        entry.foodMemoryIdString = memory.id.uuidString

        try context.save()

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)
        let refreshedEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == entryID })
        )
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .createdCandidate)
    }

    func testUpdatingTrackedFoodEntryWithResolutionExplanationSucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)
        let entryID = entry.id

        entry.foodMemoryResolutionExplanation = FoodMemoryMatchExplanation(
            resolverVersion: 1,
            topSignals: ["No candidate memories available"],
            penalties: [],
            consideredMemoryIds: [],
            winningScore: 0,
            runnerUpScore: nil
        )

        try context.save()

        let refreshedEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == entryID })
        )
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionExplanation?.resolverVersion, 1)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionExplanation?.topSignals, ["No candidate memories available"])
    }

    func testManuallyResolvingFetchedEntryWithInsertedCandidateMemorySucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let matcher = FoodMemoryMatcher()
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)

        let entryID = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<FoodEntry>(
                    predicate: #Predicate { $0.foodMemoryNeedsResolution == true }
                )
            ).first?.id
        )
        let fetchedEntry = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<FoodEntry>(
                    predicate: #Predicate { $0.id == entryID }
                )
            ).first
        )
        let snapshot = try XCTUnwrap(fetchedEntry.acceptedSnapshot)
        let result = matcher.match(snapshot: snapshot, candidates: [])
        let memory = makeMemory(
            name: snapshot.displayName,
            normalizedName: snapshot.normalizedDisplayName,
            loggedAt: snapshot.loggedAt,
            entryID: fetchedEntry.id,
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )

        context.insert(memory)
        fetchedEntry.foodMemoryNeedsResolution = false
        fetchedEntry.foodMemoryResolutionState = .createdCandidate
        fetchedEntry.foodMemoryMatchConfidence = result.confidence
        fetchedEntry.foodMemoryMatchVersion = result.explanation.resolverVersion
        fetchedEntry.foodMemoryResolvedAt = .now
        fetchedEntry.foodMemoryResolutionExplanation = result.explanation
        fetchedEntry.foodMemoryIdString = memory.id.uuidString

        try context.save()

        let refreshedEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == entryID })
        )
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .createdCandidate)
        XCTAssertEqual(refreshedEntry.foodMemoryIdString, memory.id.uuidString)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionExplanation?.resolverVersion, 1)
    }

    func testManualResolverControlFlowWithServiceLikeFetchesSucceeds() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let matcher = FoodMemoryMatcher()
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)

        let pendingDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.foodMemoryNeedsResolution == true },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt)]
        )
        let entryIDs = try context.fetch(pendingDescriptor).prefix(5).map(\.id)

        for entryID in entryIDs {
            let entryDescriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.id == entryID }
            )
            let fetchedEntry = try XCTUnwrap(context.fetch(entryDescriptor).first)
            let memories = try context.fetch(FetchDescriptor<FoodMemory>())
            let index = FoodMemoryIndex(memories: memories)
            let snapshot = try XCTUnwrap(fetchedEntry.acceptedSnapshot)
            let indexedCandidates = index.candidates(for: snapshot)
            let candidates = indexedCandidates.isEmpty ? memories : indexedCandidates
            let result = matcher.match(snapshot: snapshot, candidates: candidates)
            let memory = makeMemory(
                name: snapshot.displayName,
                normalizedName: snapshot.normalizedDisplayName,
                loggedAt: snapshot.loggedAt,
                entryID: fetchedEntry.id,
                components: [
                    FoodMemoryComponentSummary(
                        normalizedName: "grilled chicken",
                        role: .protein,
                        observationCount: 1,
                        typicalCalories: 240,
                        typicalProteinGrams: 38,
                        typicalCarbsGrams: 0,
                        typicalFatGrams: 5
                    ),
                    FoodMemoryComponentSummary(
                        normalizedName: "white rice",
                        role: .carb,
                        observationCount: 1,
                        typicalCalories: 205,
                        typicalProteinGrams: 4,
                        typicalCarbsGrams: 45,
                        typicalFatGrams: 0
                    )
                ]
            )

            context.insert(memory)
            fetchedEntry.foodMemoryNeedsResolution = false
            fetchedEntry.foodMemoryResolutionState = .createdCandidate
            fetchedEntry.foodMemoryMatchConfidence = result.confidence
            fetchedEntry.foodMemoryMatchVersion = result.explanation.resolverVersion
            fetchedEntry.foodMemoryResolvedAt = .now
            fetchedEntry.foodMemoryResolutionExplanation = result.explanation
            fetchedEntry.foodMemoryIdString = memory.id.uuidString
        }

        try context.save()

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)
    }

    func testResolverCreatesCandidateMemoryForFirstEntry() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(entry)
        let entryID = entry.id
        try service.resolvePendingEntries(limit: 5, modelContext: context)

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let refreshedEntry = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == entryID })
        )
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.displayName, "Chicken Rice Bowl")
        XCTAssertEqual(memories.first?.status, .candidate)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .createdCandidate)
        XCTAssertEqual(refreshedEntry.foodMemoryNeedsResolution, false)
        XCTAssertNotNil(refreshedEntry.foodMemoryResolutionExplanation)
    }

    func testResolverMatchesRepeatedMealToExistingMemory() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let first = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        let second = makeEntry(
            name: "Grilled Chicken Bowl with Rice",
            loggedAt: Date(timeIntervalSince1970: 1_714_086_400),
            calories: 635,
            protein: 43,
            carbs: 56,
            fat: 17,
            components: [
                component("grilled chicken", role: .protein, calories: 245, protein: 39, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 210, protein: 4, carbs: 44, fat: 1)
            ]
        )

        context.insert(first)
        context.insert(second)
        let secondID = second.id
        try service.resolvePendingEntries(limit: 5, modelContext: context)

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let refreshedSecond = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == secondID })
        )
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.observationCount, 2)
        XCTAssertEqual(refreshedSecond.foodMemoryResolutionState, .matched)
        XCTAssertEqual(refreshedSecond.foodMemoryIdString, memories.first?.id.uuidString)
        XCTAssertNotNil(refreshedSecond.foodMemoryResolutionExplanation)
    }

    func testResolverKeepsDistinctMealsSeparateWhenDominantProteinDiffers() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let chickenMeal = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        let salmonMeal = makeEntry(
            name: "Salmon Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_086_400),
            calories: 680,
            protein: 36,
            carbs: 48,
            fat: 28,
            components: [
                component("salmon", role: .protein, calories: 320, protein: 32, carbs: 0, fat: 20),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(chickenMeal)
        context.insert(salmonMeal)
        let chickenID = chickenMeal.id
        let salmonID = salmonMeal.id
        try service.resolvePendingEntries(limit: 5, modelContext: context)

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        let refreshedChicken = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == chickenID })
        )
        let refreshedSalmon = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodEntry>()).first(where: { $0.id == salmonID })
        )
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(refreshedSalmon.foodMemoryResolutionState, .createdCandidate)
        XCTAssertNotEqual(refreshedChicken.foodMemoryIdString, refreshedSalmon.foodMemoryIdString)
        XCTAssertNotNil(refreshedSalmon.foodMemoryResolutionExplanation)
    }

    func testHistoricalBackfillCreatesSnapshotsAndQueuesLegacyEntries() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let legacyEntry = makeLegacyEntry(
            name: "Protein Shake",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            input: .manual
        )

        context.insert(legacyEntry)
        try context.save()

        let backfilledCount = try service.backfillHistoricalEntries(limit: 5, modelContext: context)
        let refreshedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)
        let snapshot = try XCTUnwrap(refreshedEntry.acceptedSnapshot)

        XCTAssertEqual(backfilledCount, 1)
        XCTAssertEqual(snapshot.source, .manual)
        XCTAssertEqual(snapshot.displayName, "Protein Shake")
        XCTAssertEqual(snapshot.servingUnit, "bottle")
        XCTAssertTrue(refreshedEntry.foodMemoryNeedsResolution)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .queued)
    }

    func testMaintenanceBackfillsLegacyEntriesAndResolvesThem() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let legacyEntry = makeLegacyEntry(
            name: "Protein Shake",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            input: .manual
        )

        context.insert(legacyEntry)
        try context.save()

        let result = try service.runMaintenance(backfillLimit: 5, resolveLimit: 5, modelContext: context)
        let refreshedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)
        let memories = try context.fetch(FetchDescriptor<FoodMemory>())

        XCTAssertEqual(result.backfilledEntries, 1)
        XCTAssertEqual(result.resolvedEntries, 1)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(refreshedEntry.foodMemoryResolutionState, .createdCandidate)
        XCTAssertFalse(refreshedEntry.foodMemoryNeedsResolution)
    }

    func testShadowSummaryReflectsLegacyCoverage() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let trackedEntry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        let legacyEntry = makeLegacyEntry(
            name: "Turkey Sandwich",
            loggedAt: Date(timeIntervalSince1970: 1_714_003_600),
            input: .description
        )

        context.insert(trackedEntry)
        context.insert(legacyEntry)
        try context.save()

        let summary = try service.shadowSummary(modelContext: context)

        XCTAssertEqual(summary.totalEntries, 2)
        XCTAssertEqual(summary.trackedEntries, 1)
        XCTAssertEqual(summary.pendingEntries, 1)
        XCTAssertEqual(summary.legacyEntriesWithoutSnapshot, 1)
        XCTAssertEqual(summary.entriesWithStructuredComponents, 1)
        XCTAssertEqual(summary.totalMemories, 0)
    }

    func testCameraSuggestionsPreferMatchingMealTimeAndConfirmedMemories() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let calendar = Calendar.current

        var lunchDateComponents = DateComponents()
        lunchDateComponents.year = 2026
        lunchDateComponents.month = 4
        lunchDateComponents.day = 15
        lunchDateComponents.hour = 12
        lunchDateComponents.minute = 15
        let lunchObservedAt = try XCTUnwrap(calendar.date(from: lunchDateComponents))
        let lunchMemory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            loggedAt: lunchObservedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                )
            ]
        )
        lunchMemory.status = .confirmed
        lunchMemory.observationCount = 4
        lunchMemory.confirmedReuseCount = 3
        lunchMemory.confidenceScore = 0.94
        lunchMemory.updatedAt = lunchObservedAt
        lunchMemory.lastObservedAt = lunchObservedAt

        var dinnerDateComponents = DateComponents()
        dinnerDateComponents.year = 2026
        dinnerDateComponents.month = 4
        dinnerDateComponents.day = 15
        dinnerDateComponents.hour = 19
        dinnerDateComponents.minute = 0
        let dinnerObservedAt = try XCTUnwrap(calendar.date(from: dinnerDateComponents))
        let dinnerMemory = makeMemory(
            name: "Steak Dinner",
            normalizedName: "steak dinner",
            loggedAt: dinnerObservedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "steak",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 340,
                    typicalProteinGrams: 42,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 18
                )
            ]
        )
        dinnerMemory.status = .confirmed
        dinnerMemory.observationCount = 4
        dinnerMemory.confirmedReuseCount = 3
        dinnerMemory.confidenceScore = 0.94
        dinnerMemory.updatedAt = dinnerObservedAt
        dinnerMemory.lastObservedAt = dinnerObservedAt

        context.insert(lunchMemory)
        context.insert(dinnerMemory)
        try context.save()

        var lunchComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        lunchComponents.hour = 12
        lunchComponents.minute = 15
        let lunchtime = try XCTUnwrap(calendar.date(from: lunchComponents))

        let suggestions = try service.cameraSuggestions(limit: 5, now: lunchtime, modelContext: context)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "Chicken Rice Bowl")
        XCTAssertTrue(suggestions.first?.subtitle.localizedCaseInsensitiveContains("lunch") == true)
    }

    func testCameraSuggestionsExcludeOneOffCandidates() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()

        let candidateMemory = makeMemory(
            name: "Single Protein Shake",
            normalizedName: "single protein shake",
            loggedAt: Date(timeIntervalSince1970: 1_714_000_000),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "protein powder",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 180,
                    typicalProteinGrams: 32,
                    typicalCarbsGrams: 6,
                    typicalFatGrams: 3
                )
            ]
        )
        candidateMemory.status = .candidate
        candidateMemory.observationCount = 1
        candidateMemory.confirmedReuseCount = 0
        candidateMemory.confidenceScore = 0.95

        context.insert(candidateMemory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 5, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testCameraSuggestionsSuppressMorningOnlyItemsLateAtNight() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let calendar = Calendar.current

        var coffeeDateComponents = DateComponents()
        coffeeDateComponents.year = 2026
        coffeeDateComponents.month = 4
        coffeeDateComponents.day = 14
        coffeeDateComponents.hour = 8
        coffeeDateComponents.minute = 30
        let coffeeObservedAt = try XCTUnwrap(calendar.date(from: coffeeDateComponents))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: "morning coffee",
            loggedAt: coffeeObservedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 5,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 5
        coffeeMemory.confirmedReuseCount = 4
        coffeeMemory.confidenceScore = 0.97
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 5],
            weekdayCount: 5,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.96
        )

        context.insert(coffeeMemory)
        try context.save()

        var lateNightComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        lateNightComponents.hour = 23
        lateNightComponents.minute = 0
        let lateNight = try XCTUnwrap(calendar.date(from: lateNightComponents))

        let suggestions = try service.cameraSuggestions(limit: 5, now: lateNight, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testCameraSuggestionsUsePersistedMemoryEmoji() throws {
        let container = try ModelContainer(
            for: FoodMemory.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()

        let memory = makeMemory(
            name: "Cold Brew Coffee",
            normalizedName: "cold brew coffee",
            loggedAt: Date(),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 3,
                    typicalCalories: 5,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 4
        memory.confirmedReuseCount = 2
        memory.confidenceScore = 0.93
        memory.emoji = "🧋"

        context.insert(memory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: memory.lastObservedAt, modelContext: context)

        XCTAssertEqual(suggestions.first?.emoji, "🧋")
        XCTAssertEqual(suggestions.first?.suggestedEntry.emoji, "🧋")
    }

    func testFoodSuggestionServiceDeduplicatesStructurallyEquivalentMemories() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let primary = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        primary.status = .confirmed
        primary.observationCount = 4
        primary.confirmedReuseCount = 3
        primary.confidenceScore = 0.94

        let duplicate = makeMemory(
            name: "Grilled Chicken Bowl with Rice",
            normalizedName: FoodNormalizationService().normalizeFoodName("Grilled Chicken Bowl with Rice"),
            loggedAt: now.addingTimeInterval(-300),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 242,
                    typicalProteinGrams: 39,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 3,
                    typicalCalories: 206,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 44,
                    typicalFatGrams: 0
                )
            ]
        )
        duplicate.status = .confirmed
        duplicate.observationCount = 3
        duplicate.confirmedReuseCount = 2
        duplicate.confidenceScore = 0.9
        duplicate.aliases.append(
            FoodMemoryAlias(
                normalizedName: primary.primaryNormalizedName,
                displayName: primary.displayName,
                observationCount: 1,
                wasUserEdited: true
            )
        )

        context.insert(primary)
        context.insert(duplicate)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertEqual(suggestions.count, 1)
    }

    func testConsolidateDuplicateMemoriesMergesHistoryAndRewiresEntries() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let primary = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        primary.status = .confirmed
        primary.observationCount = 4
        primary.confirmedReuseCount = 3
        primary.confidenceScore = 0.94
        primary.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 2,
            timesTapped: 1,
            timesAccepted: 1,
            timesDismissed: 0,
            timesRefined: 0,
            lastShownAt: now,
            lastTappedAt: now,
            lastAcceptedAt: now,
            lastDismissedAt: nil,
            lastRefinedAt: nil
        )

        let duplicate = makeMemory(
            name: "Grilled Chicken Bowl with Rice",
            normalizedName: FoodNormalizationService().normalizeFoodName("Grilled Chicken Bowl with Rice"),
            loggedAt: now.addingTimeInterval(-300),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 242,
                    typicalProteinGrams: 39,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 3,
                    typicalCalories: 206,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 44,
                    typicalFatGrams: 0
                )
            ]
        )
        duplicate.status = .candidate
        duplicate.observationCount = 3
        duplicate.confirmedReuseCount = 2
        duplicate.confidenceScore = 0.9
        duplicate.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 3,
            timesTapped: 1,
            timesAccepted: 0,
            timesDismissed: 1,
            timesRefined: 0,
            lastShownAt: now.addingTimeInterval(-300),
            lastTappedAt: now.addingTimeInterval(-300),
            lastAcceptedAt: nil,
            lastDismissedAt: now.addingTimeInterval(-300),
            lastRefinedAt: nil
        )

        let primaryEntry = makeEntry(
            name: primary.displayName,
            loggedAt: now.addingTimeInterval(-60 * 30),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )
        primaryEntry.foodMemoryIdString = primary.id.uuidString

        let duplicateEntry = makeEntry(
            name: duplicate.displayName,
            loggedAt: now.addingTimeInterval(-60),
            components: [
                component("grilled chicken", role: .protein, calories: 242, protein: 39, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 206, protein: 4, carbs: 44, fat: 0)
            ]
        )
        duplicateEntry.foodMemoryIdString = duplicate.id.uuidString

        context.insert(primary)
        context.insert(duplicate)
        context.insert(primaryEntry)
        context.insert(duplicateEntry)
        try context.save()

        let mergedCount = try service.consolidateDuplicateMemories(modelContext: context)

        XCTAssertEqual(mergedCount, 1)

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)

        let mergedMemory = try XCTUnwrap(memories.first)
        XCTAssertEqual(mergedMemory.id, primary.id)
        XCTAssertEqual(mergedMemory.observationCount, 7)
        XCTAssertEqual(mergedMemory.confirmedReuseCount, 5)
        XCTAssertTrue(mergedMemory.aliases.contains { $0.displayName == "Chicken Rice Bowl" })
        XCTAssertTrue(mergedMemory.aliases.contains { $0.displayName == "Grilled Chicken Bowl with Rice" })
        XCTAssertEqual(mergedMemory.suggestionStats?.timesShown, 5)
        XCTAssertEqual(mergedMemory.suggestionStats?.timesTapped, 2)
        XCTAssertEqual(mergedMemory.suggestionStats?.timesAccepted, 1)
        XCTAssertEqual(mergedMemory.suggestionStats?.timesDismissed, 1)

        let refreshedEntries = try context.fetch(
            FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\FoodEntry.loggedAt)])
        )
        XCTAssertTrue(refreshedEntries.allSatisfy { $0.foodMemoryIdString == primary.id.uuidString })
    }

    func testFoodSuggestionServiceSuppressesAlreadyLoggedSingleUseHabitToday() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let memory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 5
        memory.confirmedReuseCount = 4
        memory.confidenceScore = 0.97

        let todaysEntry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: now.addingTimeInterval(-60 * 45),
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(memory)
        context.insert(todaysEntry)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFoodSuggestionServiceSuppressesTodayMatchWithoutAcceptedSnapshot() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let memory = makeMemory(
            name: "Protein Shake",
            normalizedName: FoodNormalizationService().normalizeFoodName("Protein Shake"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "protein powder",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 150,
                    typicalProteinGrams: 30,
                    typicalCarbsGrams: 4,
                    typicalFatGrams: 2
                )
            ]
        )
        memory.kind = .food
        memory.status = .confirmed
        memory.observationCount = 5
        memory.confirmedReuseCount = 4
        memory.confidenceScore = 0.97
        memory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 150,
            medianProteinGrams: 30,
            medianCarbsGrams: 4,
            medianFatGrams: 2,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 130,
            upperCaloriesBound: 170,
            lowerProteinBound: 26,
            upperProteinBound: 34
        )

        let todaysEntry = FoodEntry(
            name: "Protein Shake",
            mealType: FoodEntry.MealType.breakfast.rawValue,
            calories: 152,
            proteinGrams: 31,
            carbsGrams: 5,
            fatGrams: 2
        )
        todaysEntry.loggedAt = now.addingTimeInterval(-60 * 30)
        todaysEntry.input = .manual
        todaysEntry.acceptedSnapshotData = nil
        todaysEntry.acceptedComponentsData = nil

        context.insert(memory)
        context.insert(todaysEntry)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFoodSuggestionServiceSuppressesRepeatedlyIgnoredSuggestion() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let memory = makeMemory(
            name: "Greek Yogurt Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Greek Yogurt Bowl"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "greek yogurt",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 180,
                    typicalProteinGrams: 18,
                    typicalCarbsGrams: 8,
                    typicalFatGrams: 6
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 5
        memory.confirmedReuseCount = 4
        memory.confidenceScore = 0.95
        memory.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 4,
            timesTapped: 0,
            timesAccepted: 0,
            timesDismissed: 0,
            timesRefined: 0,
            lastShownAt: now.addingTimeInterval(-60 * 60),
            lastTappedAt: nil,
            lastAcceptedAt: nil,
            lastDismissedAt: nil,
            lastRefinedAt: nil
        )

        context.insert(memory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFoodSuggestionServiceSuppressesRecentlyDismissedSuggestion() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = Date(timeIntervalSince1970: 1_713_999_900)

        let memory = makeMemory(
            name: "Salmon Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Salmon Rice Bowl"),
            loggedAt: now,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "salmon",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 280,
                    typicalProteinGrams: 30,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 16
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 5
        memory.confirmedReuseCount = 4
        memory.confidenceScore = 0.95
        memory.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 3,
            timesTapped: 0,
            timesAccepted: 0,
            timesDismissed: 1,
            timesRefined: 0,
            lastShownAt: now.addingTimeInterval(-60 * 60),
            lastTappedAt: nil,
            lastAcceptedAt: nil,
            lastDismissedAt: now.addingTimeInterval(-60 * 30),
            lastRefinedAt: nil
        )

        context.insert(memory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFoodSuggestionServiceAllowsRepeatForHistoricalMultiUseCoffee() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let calendar = Calendar.current

        var currentComponents = DateComponents()
        currentComponents.year = 2026
        currentComponents.month = 4
        currentComponents.day = 20
        currentComponents.hour = 10
        currentComponents.minute = 30
        let now = try XCTUnwrap(calendar.date(from: currentComponents))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Morning Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 8,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 8
        coffeeMemory.confirmedReuseCount = 6
        coffeeMemory.confidenceScore = 0.98
        coffeeMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 0,
            upperCaloriesBound: 12,
            lowerProteinBound: 0,
            upperProteinBound: 0
        )
        coffeeMemory.servingProfile = FoodMemoryServingProfile(
            commonServingText: "1 cup",
            commonQuantity: 1,
            commonUnit: "cup",
            quantityVariance: 0
        )
        coffeeMemory.fingerprints = [
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: coffeeMemory.primaryNormalizedName),
            FoodMemoryFingerprint(version: 1, type: .mealTimeBucket, value: MealTimeBucket.breakfast.rawValue)
        ]
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 3
                counts[8] = 3
                counts[10] = 2
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 8],
            weekdayCount: 8,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.95
        )

        context.insert(coffeeMemory)

        for dayOffset in 1...5 {
            guard let first = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                  let second = calendar.date(byAdding: .minute, value: 140, to: first) else {
                continue
            }
            context.insert(
                makeEntry(
                    name: "Morning Coffee",
                    loggedAt: first,
                    calories: 8,
                    protein: 0,
                    carbs: 1,
                    fat: 0,
                    components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
                )
            )
            context.insert(
                makeEntry(
                    name: "Morning Coffee",
                    loggedAt: second,
                    calories: 8,
                    protein: 0,
                    carbs: 1,
                    fat: 0,
                    components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
                )
            )
        }

        context.insert(
            makeEntry(
                name: "Morning Coffee",
                loggedAt: now.addingTimeInterval(-60 * 150),
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
        )
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertEqual(suggestions.first?.title, "Morning Coffee")
    }

    func testFoodSuggestionServiceSkipsStaleConfirmedMemoryDuringRetrieval() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let calendar = Calendar.current

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 12,
            minute: 15
        )))

        let freshMemory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        freshMemory.status = .confirmed
        freshMemory.observationCount = 5
        freshMemory.confirmedReuseCount = 4
        freshMemory.confidenceScore = 0.95
        freshMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.94
        )

        let staleMemory = makeMemory(
            name: "Lunch Burrito",
            normalizedName: FoodNormalizationService().normalizeFoodName("Lunch Burrito"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 75),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "tortilla",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 210,
                    typicalProteinGrams: 6,
                    typicalCarbsGrams: 36,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 190,
                    typicalProteinGrams: 30,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 6
                )
            ]
        )
        staleMemory.status = .confirmed
        staleMemory.observationCount = 4
        staleMemory.confirmedReuseCount = 3
        staleMemory.confidenceScore = 0.96
        staleMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.92
        )
        staleMemory.updatedAt = staleMemory.lastObservedAt

        context.insert(freshMemory)
        context.insert(staleMemory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 5, now: now, modelContext: context)

        XCTAssertEqual(suggestions.map(\.title), ["Chicken Rice Bowl"])
    }

    func testFoodSuggestionServiceKeepsAcceptedLongTermHabitInRetrievalPool() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let calendar = Calendar.current

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 12,
            minute: 15
        )))

        let memory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 75),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 8,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 8,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 8
        memory.confirmedReuseCount = 7
        memory.confidenceScore = 0.98
        memory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 8,
            repeatedTimeBucketScore: 0.97
        )
        memory.suggestionStats = FoodMemorySuggestionStats(
            timesShown: 6,
            timesTapped: 4,
            timesAccepted: 2,
            timesDismissed: 0,
            timesRefined: 0,
            lastShownAt: now.addingTimeInterval(-60 * 60 * 24 * 3),
            lastTappedAt: now.addingTimeInterval(-60 * 60 * 24 * 3),
            lastAcceptedAt: now.addingTimeInterval(-60 * 60 * 24 * 10),
            lastDismissedAt: nil,
            lastRefinedAt: nil
        )
        memory.updatedAt = memory.lastObservedAt

        context.insert(memory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertEqual(suggestions.first?.title, "Chicken Rice Bowl")
    }

    func testFoodSuggestionServiceUsesSessionCooccurrenceToRescuePairedFood() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let calendar = Calendar.current

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 8,
            minute: 30
        )))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Morning Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 8,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.kind = .food
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 8
        coffeeMemory.confirmedReuseCount = 7
        coffeeMemory.confidenceScore = 0.98
        coffeeMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 5,
            upperCaloriesBound: 12,
            lowerProteinBound: 0,
            upperProteinBound: 0,
        )
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 3
                counts[8] = 3
                counts[9] = 2
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 8],
            weekdayCount: 8,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 8,
            repeatedTimeBucketScore: 0.96
        )

        let bagelMemory = makeMemory(
            name: "Everything Bagel",
            normalizedName: FoodNormalizationService().normalizeFoodName("Everything Bagel"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 75),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "bagel",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 280,
                    typicalProteinGrams: 10,
                    typicalCarbsGrams: 54,
                    typicalFatGrams: 4
                )
            ]
        )
        bagelMemory.kind = .food
        bagelMemory.status = .confirmed
        bagelMemory.observationCount = 4
        bagelMemory.confirmedReuseCount = 3
        bagelMemory.confidenceScore = 0.94
        bagelMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 280,
            medianProteinGrams: 10,
            medianCarbsGrams: 54,
            medianFatGrams: 4,
            medianFiberGrams: 2,
            medianSugarGrams: 5,
            lowerCaloriesBound: 260,
            upperCaloriesBound: 300,
            lowerProteinBound: 8,
            upperProteinBound: 12
        )
        bagelMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 1
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 4],
            weekdayCount: 4,
            weekendCount: 0
        )
        bagelMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.91
        )
        bagelMemory.updatedAt = bagelMemory.lastObservedAt

        context.insert(coffeeMemory)
        context.insert(bagelMemory)

        for dayOffset in [8, 15, 22] {
            let historicalSessionID = UUID()
            let historicalTime = now.addingTimeInterval(-60 * 60 * 24 * Double(dayOffset))

            let coffeeEntry = makeEntry(
                name: "Morning Coffee",
                loggedAt: historicalTime,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
            coffeeEntry.sessionId = historicalSessionID
            coffeeEntry.sessionOrder = 0
            coffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

            let bagelEntry = makeEntry(
                name: "Everything Bagel",
                loggedAt: historicalTime.addingTimeInterval(60 * 5),
                calories: 280,
                protein: 10,
                carbs: 54,
                fat: 4,
                components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
            )
            bagelEntry.sessionId = historicalSessionID
            bagelEntry.sessionOrder = 1
            bagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

            context.insert(coffeeEntry)
            context.insert(bagelEntry)
        }

        let currentSessionID = UUID()
        let currentCoffeeEntry = makeEntry(
            name: "Morning Coffee",
            loggedAt: now.addingTimeInterval(-60 * 10),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        currentCoffeeEntry.sessionId = currentSessionID
        currentCoffeeEntry.sessionOrder = 0
        currentCoffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString
        context.insert(currentCoffeeEntry)
        try context.save()

        let suggestionsWithoutSession = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)
        let suggestionsWithSession = try service.cameraSuggestions(
            limit: 3,
            now: now,
            sessionId: currentSessionID,
            modelContext: context
        )

        XCTAssertFalse(suggestionsWithoutSession.contains(where: { $0.title == "Everything Bagel" }))
        XCTAssertTrue(suggestionsWithSession.contains(where: { $0.title == "Everything Bagel" }))
    }

    func testFoodSuggestionServicePromotesRepeatedBundlesWhenMultipleAnchorsArePresent() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 8,
            minute: 30
        )))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Morning Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 4),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 8,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.kind = .food
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 8
        coffeeMemory.confirmedReuseCount = 6
        coffeeMemory.confidenceScore = 0.98
        coffeeMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 5,
            upperCaloriesBound: 12,
            lowerProteinBound: 0,
            upperProteinBound: 0
        )
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 3
                counts[8] = 3
                counts[9] = 2
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 8],
            weekdayCount: 8,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 8,
            repeatedTimeBucketScore: 0.96
        )

        let bagelMemory = makeMemory(
            name: "Everything Bagel",
            normalizedName: FoodNormalizationService().normalizeFoodName("Everything Bagel"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 6),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "bagel",
                    role: .carb,
                    observationCount: 5,
                    typicalCalories: 280,
                    typicalProteinGrams: 10,
                    typicalCarbsGrams: 54,
                    typicalFatGrams: 4
                )
            ]
        )
        bagelMemory.kind = .food
        bagelMemory.status = .confirmed
        bagelMemory.observationCount = 5
        bagelMemory.confirmedReuseCount = 4
        bagelMemory.confidenceScore = 0.95
        bagelMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 280,
            medianProteinGrams: 10,
            medianCarbsGrams: 54,
            medianFatGrams: 4,
            medianFiberGrams: 2,
            medianSugarGrams: 5,
            lowerCaloriesBound: 260,
            upperCaloriesBound: 300,
            lowerProteinBound: 8,
            upperProteinBound: 12
        )
        bagelMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 5],
            weekdayCount: 5,
            weekendCount: 0
        )
        bagelMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.9
        )

        let yogurtMemory = makeMemory(
            name: "Greek Yogurt",
            normalizedName: FoodNormalizationService().normalizeFoodName("Greek Yogurt"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 18),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "yogurt",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 140,
                    typicalProteinGrams: 16,
                    typicalCarbsGrams: 10,
                    typicalFatGrams: 4
                )
            ]
        )
        yogurtMemory.kind = .food
        yogurtMemory.status = .confirmed
        yogurtMemory.observationCount = 3
        yogurtMemory.confirmedReuseCount = 2
        yogurtMemory.confidenceScore = 0.88
        yogurtMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 140,
            medianProteinGrams: 16,
            medianCarbsGrams: 10,
            medianFatGrams: 4,
            medianFiberGrams: nil,
            medianSugarGrams: 7,
            lowerCaloriesBound: 130,
            upperCaloriesBound: 150,
            lowerProteinBound: 14,
            upperProteinBound: 18
        )
        yogurtMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 1
                counts[8] = 1
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 3],
            weekdayCount: 3,
            weekendCount: 0
        )
        yogurtMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 3,
            repeatedTimeBucketScore: 0.78
        )
        yogurtMemory.updatedAt = yogurtMemory.lastObservedAt

        let toastMemory = makeMemory(
            name: "Sourdough Toast",
            normalizedName: FoodNormalizationService().normalizeFoodName("Sourdough Toast"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 9),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "toast",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 180,
                    typicalProteinGrams: 6,
                    typicalCarbsGrams: 32,
                    typicalFatGrams: 3
                )
            ]
        )
        toastMemory.kind = .food
        toastMemory.status = .confirmed
        toastMemory.observationCount = 4
        toastMemory.confirmedReuseCount = 3
        toastMemory.confidenceScore = 0.92
        toastMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 180,
            medianProteinGrams: 6,
            medianCarbsGrams: 32,
            medianFatGrams: 3,
            medianFiberGrams: 2,
            medianSugarGrams: 2,
            lowerCaloriesBound: 170,
            upperCaloriesBound: 190,
            lowerProteinBound: 5,
            upperProteinBound: 7
        )
        toastMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 1
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 4],
            weekdayCount: 4,
            weekendCount: 0
        )
        toastMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.86
        )

        [coffeeMemory, bagelMemory, yogurtMemory, toastMemory].forEach(context.insert)

        for dayOffset in [8, 15, 22] {
            let trioSessionID = UUID()
            let sessionTime = now.addingTimeInterval(-60 * 60 * 24 * Double(dayOffset))

            let coffeeEntry = makeEntry(
                name: "Morning Coffee",
                loggedAt: sessionTime,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
            coffeeEntry.sessionId = trioSessionID
            coffeeEntry.sessionOrder = 0
            coffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

            let bagelEntry = makeEntry(
                name: "Everything Bagel",
                loggedAt: sessionTime.addingTimeInterval(60 * 5),
                calories: 280,
                protein: 10,
                carbs: 54,
                fat: 4,
                components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
            )
            bagelEntry.sessionId = trioSessionID
            bagelEntry.sessionOrder = 1
            bagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

            let yogurtEntry = makeEntry(
                name: "Greek Yogurt",
                loggedAt: sessionTime.addingTimeInterval(60 * 10),
                calories: 140,
                protein: 16,
                carbs: 10,
                fat: 4,
                components: [component("yogurt", role: .protein, calories: 140, protein: 16, carbs: 10, fat: 4)]
            )
            yogurtEntry.sessionId = trioSessionID
            yogurtEntry.sessionOrder = 2
            yogurtEntry.foodMemoryIdString = yogurtMemory.id.uuidString

            context.insert(coffeeEntry)
            context.insert(bagelEntry)
            context.insert(yogurtEntry)
        }

        for dayOffset in [5, 12, 19] {
            let pairSessionID = UUID()
            let sessionTime = now.addingTimeInterval(-60 * 60 * 24 * Double(dayOffset))

            let coffeeEntry = makeEntry(
                name: "Morning Coffee",
                loggedAt: sessionTime,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
            coffeeEntry.sessionId = pairSessionID
            coffeeEntry.sessionOrder = 0
            coffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

            let toastEntry = makeEntry(
                name: "Sourdough Toast",
                loggedAt: sessionTime.addingTimeInterval(60 * 7),
                calories: 180,
                protein: 6,
                carbs: 32,
                fat: 3,
                components: [component("toast", role: .carb, calories: 180, protein: 6, carbs: 32, fat: 3)]
            )
            toastEntry.sessionId = pairSessionID
            toastEntry.sessionOrder = 1
            toastEntry.foodMemoryIdString = toastMemory.id.uuidString

            context.insert(coffeeEntry)
            context.insert(toastEntry)
        }

        let bagelLoggedToday = makeEntry(
            name: "Everything Bagel",
            loggedAt: now.addingTimeInterval(-60 * 40),
            calories: 280,
            protein: 10,
            carbs: 54,
            fat: 4,
            components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
        )
        bagelLoggedToday.sessionId = UUID()
        bagelLoggedToday.sessionOrder = 0
        bagelLoggedToday.foodMemoryIdString = bagelMemory.id.uuidString
        context.insert(bagelLoggedToday)

        let coffeeOnlySessionID = UUID()
        let coffeeOnlyEntry = makeEntry(
            name: "Morning Coffee",
            loggedAt: now.addingTimeInterval(-60 * 12),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        coffeeOnlyEntry.sessionId = coffeeOnlySessionID
        coffeeOnlyEntry.sessionOrder = 0
        coffeeOnlyEntry.foodMemoryIdString = coffeeMemory.id.uuidString
        context.insert(coffeeOnlyEntry)

        let bundleSessionID = UUID()
        let bundleCoffeeEntry = makeEntry(
            name: "Morning Coffee",
            loggedAt: now.addingTimeInterval(-60 * 22),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        bundleCoffeeEntry.sessionId = bundleSessionID
        bundleCoffeeEntry.sessionOrder = 0
        bundleCoffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

        let bundleBagelEntry = makeEntry(
            name: "Everything Bagel",
            loggedAt: now.addingTimeInterval(-60 * 17),
            calories: 280,
            protein: 10,
            carbs: 54,
            fat: 4,
            components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
        )
        bundleBagelEntry.sessionId = bundleSessionID
        bundleBagelEntry.sessionOrder = 1
        bundleBagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

        context.insert(bundleCoffeeEntry)
        context.insert(bundleBagelEntry)
        try context.save()

        let singleAnchorSuggestions = try service.cameraSuggestions(
            limit: 2,
            now: now,
            sessionId: coffeeOnlySessionID,
            modelContext: context
        )
        let bundleSuggestions = try service.cameraSuggestions(
            limit: 2,
            now: now,
            sessionId: bundleSessionID,
            modelContext: context
        )

        XCTAssertEqual(singleAnchorSuggestions.first?.title, "Sourdough Toast")
        XCTAssertEqual(bundleSuggestions.first?.title, "Greek Yogurt")
    }

    func testFoodSuggestionServicePrefersImmediateNextSessionItem() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 8,
            minute: 15
        )))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Morning Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 4),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 6,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.kind = .food
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 6
        coffeeMemory.confirmedReuseCount = 5
        coffeeMemory.confidenceScore = 0.96
        coffeeMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 5,
            upperCaloriesBound: 12,
            lowerProteinBound: 0,
            upperProteinBound: 0
        )
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 3
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 6],
            weekdayCount: 6,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 6,
            repeatedTimeBucketScore: 0.95
        )

        let bagelMemory = makeMemory(
            name: "Everything Bagel",
            normalizedName: FoodNormalizationService().normalizeFoodName("Everything Bagel"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 6),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "bagel",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 280,
                    typicalProteinGrams: 10,
                    typicalCarbsGrams: 54,
                    typicalFatGrams: 4
                )
            ]
        )
        bagelMemory.kind = .food
        bagelMemory.status = .confirmed
        bagelMemory.observationCount = 4
        bagelMemory.confirmedReuseCount = 3
        bagelMemory.confidenceScore = 0.9
        bagelMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 280,
            medianProteinGrams: 10,
            medianCarbsGrams: 54,
            medianFatGrams: 4,
            medianFiberGrams: 2,
            medianSugarGrams: 5,
            lowerCaloriesBound: 260,
            upperCaloriesBound: 300,
            lowerProteinBound: 8,
            upperProteinBound: 12
        )
        bagelMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 1
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 4],
            weekdayCount: 4,
            weekendCount: 0
        )
        bagelMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.88
        )

        let yogurtMemory = makeMemory(
            name: "Greek Yogurt",
            normalizedName: FoodNormalizationService().normalizeFoodName("Greek Yogurt"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 6),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "yogurt",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 140,
                    typicalProteinGrams: 16,
                    typicalCarbsGrams: 10,
                    typicalFatGrams: 4
                )
            ]
        )
        yogurtMemory.kind = .food
        yogurtMemory.status = .confirmed
        yogurtMemory.observationCount = 4
        yogurtMemory.confirmedReuseCount = 3
        yogurtMemory.confidenceScore = 0.9
        yogurtMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 140,
            medianProteinGrams: 16,
            medianCarbsGrams: 10,
            medianFatGrams: 4,
            medianFiberGrams: nil,
            medianSugarGrams: 7,
            lowerCaloriesBound: 130,
            upperCaloriesBound: 150,
            lowerProteinBound: 14,
            upperProteinBound: 18
        )
        yogurtMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 1
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 4],
            weekdayCount: 4,
            weekendCount: 0
        )
        yogurtMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.88
        )

        [coffeeMemory, bagelMemory, yogurtMemory].forEach(context.insert)

        for dayOffset in [6, 13, 20] {
            let sessionID = UUID()
            let sessionTime = now.addingTimeInterval(-60 * 60 * 24 * Double(dayOffset))

            let coffeeEntry = makeEntry(
                name: "Morning Coffee",
                loggedAt: sessionTime,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
            coffeeEntry.sessionId = sessionID
            coffeeEntry.sessionOrder = 0
            coffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

            let bagelEntry = makeEntry(
                name: "Everything Bagel",
                loggedAt: sessionTime.addingTimeInterval(60 * 5),
                calories: 280,
                protein: 10,
                carbs: 54,
                fat: 4,
                components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
            )
            bagelEntry.sessionId = sessionID
            bagelEntry.sessionOrder = 1
            bagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

            let yogurtEntry = makeEntry(
                name: "Greek Yogurt",
                loggedAt: sessionTime.addingTimeInterval(60 * 10),
                calories: 140,
                protein: 16,
                carbs: 10,
                fat: 4,
                components: [component("yogurt", role: .protein, calories: 140, protein: 16, carbs: 10, fat: 4)]
            )
            yogurtEntry.sessionId = sessionID
            yogurtEntry.sessionOrder = 2
            yogurtEntry.foodMemoryIdString = yogurtMemory.id.uuidString

            context.insert(coffeeEntry)
            context.insert(bagelEntry)
            context.insert(yogurtEntry)
        }

        let currentSessionID = UUID()
        let currentCoffeeEntry = makeEntry(
            name: "Morning Coffee",
            loggedAt: now.addingTimeInterval(-60 * 8),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        currentCoffeeEntry.sessionId = currentSessionID
        currentCoffeeEntry.sessionOrder = 0
        currentCoffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString
        context.insert(currentCoffeeEntry)
        try context.save()

        let suggestions = try service.cameraSuggestions(
            limit: 2,
            now: now,
            sessionId: currentSessionID,
            modelContext: context
        )

        XCTAssertEqual(suggestions.first?.title, "Everything Bagel")
    }

    func testFoodSuggestionServiceSuppressesExtrasWhenSessionUsuallyEndsHere() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 8,
            minute: 45
        )))

        let coffeeMemory = makeMemory(
            name: "Morning Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Morning Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 5),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 7,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        coffeeMemory.kind = .food
        coffeeMemory.status = .confirmed
        coffeeMemory.observationCount = 7
        coffeeMemory.confirmedReuseCount = 5
        coffeeMemory.confidenceScore = 0.97
        coffeeMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 5,
            upperCaloriesBound: 12,
            lowerProteinBound: 0,
            upperProteinBound: 0
        )
        coffeeMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 3
                counts[8] = 3
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 7],
            weekdayCount: 7,
            weekendCount: 0
        )
        coffeeMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 7,
            repeatedTimeBucketScore: 0.95
        )

        let bagelMemory = makeMemory(
            name: "Everything Bagel",
            normalizedName: FoodNormalizationService().normalizeFoodName("Everything Bagel"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 5),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "bagel",
                    role: .carb,
                    observationCount: 5,
                    typicalCalories: 280,
                    typicalProteinGrams: 10,
                    typicalCarbsGrams: 54,
                    typicalFatGrams: 4
                )
            ]
        )
        bagelMemory.kind = .food
        bagelMemory.status = .confirmed
        bagelMemory.observationCount = 5
        bagelMemory.confirmedReuseCount = 4
        bagelMemory.confidenceScore = 0.94
        bagelMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 280,
            medianProteinGrams: 10,
            medianCarbsGrams: 54,
            medianFatGrams: 4,
            medianFiberGrams: 2,
            medianSugarGrams: 5,
            lowerCaloriesBound: 260,
            upperCaloriesBound: 300,
            lowerProteinBound: 8,
            upperProteinBound: 12
        )
        bagelMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 2
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 5],
            weekdayCount: 5,
            weekendCount: 0
        )
        bagelMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.9
        )

        let yogurtMemory = makeMemory(
            name: "Greek Yogurt",
            normalizedName: FoodNormalizationService().normalizeFoodName("Greek Yogurt"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "yogurt",
                    role: .protein,
                    observationCount: 6,
                    typicalCalories: 140,
                    typicalProteinGrams: 16,
                    typicalCarbsGrams: 10,
                    typicalFatGrams: 4
                )
            ]
        )
        yogurtMemory.kind = .food
        yogurtMemory.status = .confirmed
        yogurtMemory.observationCount = 6
        yogurtMemory.confirmedReuseCount = 4
        yogurtMemory.confidenceScore = 0.95
        yogurtMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 140,
            medianProteinGrams: 16,
            medianCarbsGrams: 10,
            medianFatGrams: 4,
            medianFiberGrams: nil,
            medianSugarGrams: 7,
            lowerCaloriesBound: 130,
            upperCaloriesBound: 150,
            lowerProteinBound: 14,
            upperProteinBound: 18
        )
        yogurtMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[7] = 2
                counts[8] = 3
                counts[9] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.breakfast.rawValue: 6],
            weekdayCount: 6,
            weekendCount: 0
        )
        yogurtMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 6,
            repeatedTimeBucketScore: 0.92
        )

        [coffeeMemory, bagelMemory, yogurtMemory].forEach(context.insert)

        for dayOffset in [6, 13, 20, 27] {
            let sessionID = UUID()
            let sessionTime = now.addingTimeInterval(-60 * 60 * 24 * Double(dayOffset))

            let coffeeEntry = makeEntry(
                name: "Morning Coffee",
                loggedAt: sessionTime,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
            coffeeEntry.sessionId = sessionID
            coffeeEntry.sessionOrder = 0
            coffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

            let bagelEntry = makeEntry(
                name: "Everything Bagel",
                loggedAt: sessionTime.addingTimeInterval(60 * 5),
                calories: 280,
                protein: 10,
                carbs: 54,
                fat: 4,
                components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
            )
            bagelEntry.sessionId = sessionID
            bagelEntry.sessionOrder = 1
            bagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

            context.insert(coffeeEntry)
            context.insert(bagelEntry)
        }

        let currentSessionID = UUID()
        let currentCoffeeEntry = makeEntry(
            name: "Morning Coffee",
            loggedAt: now.addingTimeInterval(-60 * 12),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        currentCoffeeEntry.sessionId = currentSessionID
        currentCoffeeEntry.sessionOrder = 0
        currentCoffeeEntry.foodMemoryIdString = coffeeMemory.id.uuidString

        let currentBagelEntry = makeEntry(
            name: "Everything Bagel",
            loggedAt: now.addingTimeInterval(-60 * 7),
            calories: 280,
            protein: 10,
            carbs: 54,
            fat: 4,
            components: [component("bagel", role: .carb, calories: 280, protein: 10, carbs: 54, fat: 4)]
        )
        currentBagelEntry.sessionId = currentSessionID
        currentBagelEntry.sessionOrder = 1
        currentBagelEntry.foodMemoryIdString = bagelMemory.id.uuidString

        context.insert(currentCoffeeEntry)
        context.insert(currentBagelEntry)
        try context.save()

        let suggestionsWithoutSession = try service.cameraSuggestions(
            limit: 3,
            now: now,
            modelContext: context
        )
        let suggestionsWithSession = try service.cameraSuggestions(
            limit: 3,
            now: now,
            sessionId: currentSessionID,
            modelContext: context
        )

        XCTAssertTrue(suggestionsWithoutSession.contains(where: { $0.title == "Greek Yogurt" }))
        XCTAssertFalse(suggestionsWithSession.contains(where: { $0.title == "Greek Yogurt" }))
    }

    func testFoodSuggestionServiceRanksUsingTargetDateContext() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let calendar = Calendar.current

        let breakfastTime = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 8,
            minute: 0
        )))
        let dinnerTime = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 19,
            minute: 0
        )))

        let breakfastMemory = makeMemory(
            name: "Greek Yogurt Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Greek Yogurt Bowl"),
            loggedAt: breakfastTime,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "greek yogurt",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 180,
                    typicalProteinGrams: 18,
                    typicalCarbsGrams: 8,
                    typicalFatGrams: 6
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "berries",
                    role: .fruit,
                    observationCount: 4,
                    typicalCalories: 40,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 10,
                    typicalFatGrams: 0
                )
            ]
        )
        breakfastMemory.status = .confirmed
        breakfastMemory.observationCount = 4
        breakfastMemory.confirmedReuseCount = 3
        breakfastMemory.confidenceScore = 0.95

        let dinnerMemory = makeMemory(
            name: "Salmon Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Salmon Rice Bowl"),
            loggedAt: dinnerTime,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "salmon",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 280,
                    typicalProteinGrams: 30,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 16
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        dinnerMemory.status = .confirmed
        dinnerMemory.observationCount = 4
        dinnerMemory.confirmedReuseCount = 3
        dinnerMemory.confidenceScore = 0.95

        context.insert(breakfastMemory)
        context.insert(dinnerMemory)
        try context.save()

        let suggestions = try service.cameraSuggestions(
            limit: 2,
            now: dinnerTime,
            targetDate: breakfastTime,
            modelContext: context
        )

        XCTAssertEqual(suggestions.first?.title, "Greek Yogurt Bowl")
    }

    func testFoodSuggestionServiceKeepsModeratelyLunchAlignedConfirmedMealVisible() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 13,
            minute: 0
        )))

        let lunchMemory = makeMemory(
            name: "Turkey Sandwich Lunch",
            normalizedName: FoodNormalizationService().normalizeFoodName("Turkey Sandwich Lunch"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "turkey",
                    role: .protein,
                    observationCount: 6,
                    typicalCalories: 120,
                    typicalProteinGrams: 22,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 2
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "bread",
                    role: .carb,
                    observationCount: 6,
                    typicalCalories: 160,
                    typicalProteinGrams: 6,
                    typicalCarbsGrams: 30,
                    typicalFatGrams: 2
                )
            ]
        )
        lunchMemory.kind = .meal
        lunchMemory.status = .confirmed
        lunchMemory.observationCount = 6
        lunchMemory.confirmedReuseCount = 4
        lunchMemory.confidenceScore = 0.95
        lunchMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 430,
            medianProteinGrams: 28,
            medianCarbsGrams: 38,
            medianFatGrams: 8,
            medianFiberGrams: 3,
            medianSugarGrams: 4,
            lowerCaloriesBound: 390,
            upperCaloriesBound: 470,
            lowerProteinBound: 24,
            upperProteinBound: 32
        )
        lunchMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[18] = 3
                counts[19] = 2
                counts[20] = 1
                return counts
            }(),
            bucketCounts: [
                MealTimeBucket.lunch.rawValue: 1,
                MealTimeBucket.dinner.rawValue: 5
            ],
            weekdayCount: 6,
            weekendCount: 0
        )
        lunchMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 6,
            repeatedTimeBucketScore: 0.88
        )

        context.insert(lunchMemory)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.contains(where: { $0.title == "Turkey Sandwich Lunch" }))
    }

    func testFoodSuggestionServiceCanShowStrongHabitAcrossMealBuckets() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 13,
            minute: 15
        )))

        let strongDinnerHabit = makeMemory(
            name: "Salmon Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Salmon Rice Bowl"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "salmon",
                    role: .protein,
                    observationCount: 8,
                    typicalCalories: 280,
                    typicalProteinGrams: 30,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 16
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 8,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        strongDinnerHabit.kind = .meal
        strongDinnerHabit.status = .confirmed
        strongDinnerHabit.observationCount = 8
        strongDinnerHabit.confirmedReuseCount = 6
        strongDinnerHabit.confidenceScore = 0.97
        strongDinnerHabit.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 540,
            medianProteinGrams: 34,
            medianCarbsGrams: 45,
            medianFatGrams: 16,
            medianFiberGrams: 2,
            medianSugarGrams: 1,
            lowerCaloriesBound: 500,
            upperCaloriesBound: 580,
            lowerProteinBound: 30,
            upperProteinBound: 38
        )
        strongDinnerHabit.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[18] = 3
                counts[19] = 3
                counts[20] = 2
                return counts
            }(),
            bucketCounts: [MealTimeBucket.dinner.rawValue: 8],
            weekdayCount: 8,
            weekendCount: 0
        )
        strongDinnerHabit.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 8,
            repeatedTimeBucketScore: 0.9
        )

        context.insert(strongDinnerHabit)
        try context.save()

        let suggestions = try service.cameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertTrue(suggestions.contains(where: { $0.title == "Salmon Rice Bowl" }))
    }

    func testFoodSuggestionDebugSummaryReportsStageBreakdown() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 20,
            hour: 13,
            minute: 0
        )))

        let visibleLunchMemory = makeMemory(
            name: "Chicken Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Bowl"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "chicken",
                    role: .protein,
                    observationCount: 5,
                    typicalCalories: 220,
                    typicalProteinGrams: 35,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 6
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "rice",
                    role: .carb,
                    observationCount: 5,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        visibleLunchMemory.kind = .meal
        visibleLunchMemory.status = .confirmed
        visibleLunchMemory.observationCount = 5
        visibleLunchMemory.confirmedReuseCount = 4
        visibleLunchMemory.confidenceScore = 0.95
        visibleLunchMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[12] = 2
                counts[13] = 2
                counts[14] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.lunch.rawValue: 5],
            weekdayCount: 5,
            weekendCount: 0
        )
        visibleLunchMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 5,
            repeatedTimeBucketScore: 0.95
        )

        let staleMemory = makeMemory(
            name: "Old Pasta Lunch",
            normalizedName: FoodNormalizationService().normalizeFoodName("Old Pasta Lunch"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 120),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "pasta",
                    role: .carb,
                    observationCount: 2,
                    typicalCalories: 320,
                    typicalProteinGrams: 10,
                    typicalCarbsGrams: 58,
                    typicalFatGrams: 7
                )
            ]
        )
        staleMemory.kind = .meal
        staleMemory.status = .candidate
        staleMemory.observationCount = 2
        staleMemory.confirmedReuseCount = 0
        staleMemory.confidenceScore = 0.6
        staleMemory.timeProfile = visibleLunchMemory.timeProfile
        staleMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 2,
            repeatedTimeBucketScore: 0.7
        )

        let alreadyLoggedMemory = makeMemory(
            name: "Daily Coffee",
            normalizedName: FoodNormalizationService().normalizeFoodName("Daily Coffee"),
            loggedAt: now.addingTimeInterval(-60 * 60 * 24),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 4,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        alreadyLoggedMemory.kind = .food
        alreadyLoggedMemory.status = .confirmed
        alreadyLoggedMemory.observationCount = 4
        alreadyLoggedMemory.confirmedReuseCount = 3
        alreadyLoggedMemory.confidenceScore = 0.92
        alreadyLoggedMemory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 8,
            medianProteinGrams: 0,
            medianCarbsGrams: 1,
            medianFatGrams: 0,
            medianFiberGrams: nil,
            medianSugarGrams: nil,
            lowerCaloriesBound: 8,
            upperCaloriesBound: 8,
            lowerProteinBound: 0,
            upperProteinBound: 0
        )
        alreadyLoggedMemory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: {
                var counts = Array(repeating: 0, count: 24)
                counts[12] = 1
                counts[13] = 2
                counts[14] = 1
                return counts
            }(),
            bucketCounts: [MealTimeBucket.lunch.rawValue: 4],
            weekdayCount: 4,
            weekendCount: 0
        )
        alreadyLoggedMemory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 4,
            repeatedTimeBucketScore: 0.9
        )

        [visibleLunchMemory, staleMemory, alreadyLoggedMemory].forEach(context.insert)

        let chickenComponents = [
            component("chicken", role: .protein, calories: 220, protein: 35, carbs: 0, fat: 6),
            component("rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
        ]
        let chickenEntryOne = makeEntry(
            name: "Chicken Bowl",
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 3),
            components: chickenComponents
        )
        chickenEntryOne.foodMemoryIdString = visibleLunchMemory.id.uuidString
        let chickenEntryTwo = makeEntry(
            name: "Chicken Bowl",
            loggedAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            components: chickenComponents
        )
        chickenEntryTwo.foodMemoryIdString = visibleLunchMemory.id.uuidString
        context.insert(chickenEntryOne)
        context.insert(chickenEntryTwo)

        let previousCoffee = makeEntry(
            name: "Daily Coffee",
            loggedAt: now.addingTimeInterval(-60 * 60 * 24),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        previousCoffee.foodMemoryIdString = alreadyLoggedMemory.id.uuidString
        context.insert(previousCoffee)

        let todayCoffee = makeEntry(
            name: "Daily Coffee",
            loggedAt: now.addingTimeInterval(-60 * 30),
            calories: 8,
            protein: 0,
            carbs: 1,
            fat: 0,
            components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
        )
        todayCoffee.foodMemoryIdString = alreadyLoggedMemory.id.uuidString
        context.insert(todayCoffee)
        try context.save()

        let debugSummary = try service.debugCameraSuggestions(limit: 3, now: now, modelContext: context)

        XCTAssertEqual(debugSummary.totalMemories, 3)
        XCTAssertEqual(debugSummary.patternCount, 2)
        XCTAssertGreaterThan(debugSummary.suppressedAlreadyTodayCount, 0)
        XCTAssertTrue(debugSummary.shownSuggestionTitles.contains("Chicken Bowl"))
    }

    func testResolvingOnDifferentDayIncrementsDistinctObservationDays() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()

        let calendar = Calendar.current
        let firstLoggedAt = Date(timeIntervalSince1970: 1_714_000_000)
        let secondLoggedAt = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: firstLoggedAt)
        )

        let memory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            loggedAt: firstLoggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 2
        memory.confirmedReuseCount = 1

        let entry = makeEntry(
            name: "Chicken Rice Bowl",
            loggedAt: secondLoggedAt,
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ]
        )

        context.insert(memory)
        context.insert(entry)
        try context.save()

        _ = try service.resolvePendingEntries(limit: 5, modelContext: context)

        let refreshedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<FoodMemory>()).first)
        XCTAssertEqual(refreshedMemory.qualitySignals?.distinctObservationDays, 2)
    }

    func testResolvingEntriesBuildsRepeatPatternForSameDayRepeats() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodMemoryService()
        let calendar = Calendar.current

        let firstLoggedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 19,
            hour: 8,
            minute: 0
        )))
        let secondLoggedAt = try XCTUnwrap(calendar.date(byAdding: .minute, value: 150, to: firstLoggedAt))
        let thirdLoggedAt = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstLoggedAt))

        context.insert(
            makeEntry(
                name: "Morning Coffee",
                loggedAt: firstLoggedAt,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
        )
        context.insert(
            makeEntry(
                name: "Morning Coffee",
                loggedAt: secondLoggedAt,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
        )
        context.insert(
            makeEntry(
                name: "Morning Coffee",
                loggedAt: thirdLoggedAt,
                calories: 8,
                protein: 0,
                carbs: 1,
                fat: 0,
                components: [component("coffee", role: .drink, calories: 8, protein: 0, carbs: 1, fat: 0)]
            )
        )
        try context.save()

        _ = try service.resolvePendingEntries(limit: 10, modelContext: context)

        let refreshedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<FoodMemory>()).first)
        let repeatPattern = try XCTUnwrap(refreshedMemory.repeatPattern)
        XCTAssertEqual(repeatPattern.distinctConsumptionDays, 2)
        XCTAssertEqual(repeatPattern.daysWithMultipleUses, 1)
        XCTAssertEqual(repeatPattern.maxUsesInDay, 2)
        XCTAssertEqual(repeatPattern.averageUsesPerDay, 1.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeatPattern.averageRepeatGapMinutes), 150, accuracy: 0.001)
    }

    func testRecordingSuggestionOutcomesPersistsFeedbackStats() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let loggedAt = Date(timeIntervalSince1970: 1_776_668_400)

        let memory = makeMemory(
            name: "Morning Coffee",
            normalizedName: "morning coffee",
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 1,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 4
        context.insert(memory)
        try context.save()

        try service.recordOutcome(.shown, for: memory.id, at: loggedAt, modelContext: context)
        try service.recordOutcome(.tapped, for: memory.id, at: loggedAt, modelContext: context)
        try service.recordOutcome(.refined, for: memory.id, at: loggedAt, modelContext: context)

        let refreshedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<FoodMemory>()).first)
        let suggestionStats = try XCTUnwrap(refreshedMemory.suggestionStats)
        XCTAssertEqual(suggestionStats.timesShown, 1)
        XCTAssertEqual(suggestionStats.timesTapped, 1)
        XCTAssertEqual(suggestionStats.timesAccepted, 1)
        XCTAssertEqual(suggestionStats.timesRefined, 1)
        XCTAssertEqual(suggestionStats.lastShownAt, loggedAt)
        XCTAssertEqual(suggestionStats.lastTappedAt, loggedAt)
        XCTAssertEqual(suggestionStats.lastAcceptedAt, loggedAt)
        XCTAssertEqual(suggestionStats.lastRefinedAt, loggedAt)
    }

    func testReconcilingShownSuggestionsStrengthensMatchingSavedItem() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let loggedAt = Date(timeIntervalSince1970: 1_776_668_400)

        let memory = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: "chicken rice bowl",
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.status = .confirmed
        memory.observationCount = 4
        memory.confirmedReuseCount = 3
        context.insert(memory)
        try context.save()

        let savedSnapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .description,
            kind: .meal,
            displayName: "Chicken Rice Bowl",
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            nameAliases: FoodNormalizationService().aliasCandidates(for: "Chicken Rice Bowl"),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: 620,
            totalProteinGrams: 42,
            totalCarbsGrams: 58,
            totalFatGrams: 16,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ],
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: .lunch,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )

        try service.reconcileShownSuggestions(
            [memory.id],
            preferredMemoryID: nil,
            with: savedSnapshot,
            isRefined: false,
            modelContext: context
        )

        let refreshedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<FoodMemory>()).first)
        let suggestionStats = try XCTUnwrap(refreshedMemory.suggestionStats)
        XCTAssertEqual(suggestionStats.timesAccepted, 1)
        XCTAssertEqual(suggestionStats.lastAcceptedAt, loggedAt)
    }

    func testReconcilingShownSuggestionsDoesNotPenalizeNonMatchingSavedItem() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let loggedAt = Date(timeIntervalSince1970: 1_776_668_400)

        let memory = makeMemory(
            name: "Morning Coffee",
            normalizedName: "morning coffee",
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "coffee",
                    role: .drink,
                    observationCount: 1,
                    typicalCalories: 8,
                    typicalProteinGrams: 0,
                    typicalCarbsGrams: 1,
                    typicalFatGrams: 0
                )
            ]
        )
        memory.kind = .food
        memory.status = .confirmed
        memory.observationCount = 4
        memory.confirmedReuseCount = 3
        context.insert(memory)
        try context.save()

        let savedSnapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .description,
            kind: .meal,
            displayName: "Turkey Sandwich",
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName("Turkey Sandwich"),
            nameAliases: FoodNormalizationService().aliasCandidates(for: "Turkey Sandwich"),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 sandwich",
            servingQuantity: 1,
            servingUnit: "sandwich",
            totalCalories: 430,
            totalProteinGrams: 28,
            totalCarbsGrams: 38,
            totalFatGrams: 18,
            totalFiberGrams: 3,
            totalSugarGrams: 4,
            components: [
                component("turkey", role: .protein, calories: 120, protein: 22, carbs: 0, fat: 2),
                component("bread", role: .carb, calories: 160, protein: 6, carbs: 30, fat: 2)
            ],
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: .lunch,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )

        try service.reconcileShownSuggestions(
            [memory.id],
            preferredMemoryID: nil,
            with: savedSnapshot,
            isRefined: false,
            modelContext: context
        )

        let refreshedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<FoodMemory>()).first)
        XCTAssertNil(refreshedMemory.suggestionStats)
    }

    func testReconcilingShownSuggestionsConsolidatesMultipleMatchingMemories() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let loggedAt = Date(timeIntervalSince1970: 1_776_668_400)

        let primary = makeMemory(
            name: "Chicken Rice Bowl",
            normalizedName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 4,
                    typicalCalories: 240,
                    typicalProteinGrams: 38,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 4,
                    typicalCalories: 205,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 45,
                    typicalFatGrams: 0
                )
            ]
        )
        primary.status = .confirmed
        primary.observationCount = 4
        primary.confirmedReuseCount = 3
        primary.confidenceScore = 0.94

        let duplicate = makeMemory(
            name: "Grilled Chicken Bowl with Rice",
            normalizedName: FoodNormalizationService().normalizeFoodName("Grilled Chicken Bowl with Rice"),
            loggedAt: loggedAt.addingTimeInterval(-300),
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "grilled chicken",
                    role: .protein,
                    observationCount: 3,
                    typicalCalories: 242,
                    typicalProteinGrams: 39,
                    typicalCarbsGrams: 0,
                    typicalFatGrams: 5
                ),
                FoodMemoryComponentSummary(
                    normalizedName: "white rice",
                    role: .carb,
                    observationCount: 3,
                    typicalCalories: 206,
                    typicalProteinGrams: 4,
                    typicalCarbsGrams: 44,
                    typicalFatGrams: 0
                )
            ]
        )
        duplicate.status = .candidate
        duplicate.observationCount = 3
        duplicate.confirmedReuseCount = 2
        duplicate.confidenceScore = 0.9
        duplicate.aliases.append(
            FoodMemoryAlias(
                normalizedName: primary.primaryNormalizedName,
                displayName: primary.displayName,
                observationCount: 1,
                wasUserEdited: true
            )
        )

        context.insert(primary)
        context.insert(duplicate)
        try context.save()

        let savedSnapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .description,
            kind: .meal,
            displayName: "Chicken Rice Bowl",
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName("Chicken Rice Bowl"),
            nameAliases: FoodNormalizationService().aliasCandidates(for: "Chicken Rice Bowl"),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
            servingText: "1 bowl",
            servingQuantity: 1,
            servingUnit: "bowl",
            totalCalories: 620,
            totalProteinGrams: 42,
            totalCarbsGrams: 58,
            totalFatGrams: 16,
            totalFiberGrams: 5,
            totalSugarGrams: 4,
            components: [
                component("grilled chicken", role: .protein, calories: 240, protein: 38, carbs: 0, fat: 5),
                component("white rice", role: .carb, calories: 205, protein: 4, carbs: 45, fat: 0)
            ],
            notes: nil,
            confidence: .high,
            loggedAt: loggedAt,
            mealTimeBucket: .lunch,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )

        try service.reconcileShownSuggestions(
            [primary.id, duplicate.id],
            preferredMemoryID: nil,
            with: savedSnapshot,
            isRefined: false,
            modelContext: context
        )

        let memories = try context.fetch(FetchDescriptor<FoodMemory>())
        XCTAssertEqual(memories.count, 1)

        let mergedMemory = try XCTUnwrap(memories.first)
        XCTAssertEqual(mergedMemory.id, primary.id)
        XCTAssertEqual(mergedMemory.observationCount, 7)
        XCTAssertEqual(mergedMemory.suggestionStats?.timesAccepted, 2)
    }

    func testRecordingDismissedOutcomeUpdatesBatchOfSuggestions() throws {
        let schema = Schema([
            FoodEntry.self,
            FoodMemory.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let service = FoodSuggestionService()
        let loggedAt = Date(timeIntervalSince1970: 1_776_668_400)

        let firstMemory = makeMemory(
            name: "Overnight Oats",
            normalizedName: "overnight oats",
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "oats",
                    role: .carb,
                    observationCount: 1,
                    typicalCalories: 150,
                    typicalProteinGrams: 5,
                    typicalCarbsGrams: 27,
                    typicalFatGrams: 3
                )
            ]
        )
        firstMemory.status = .confirmed
        firstMemory.observationCount = 4

        let secondMemory = makeMemory(
            name: "Greek Yogurt Bowl",
            normalizedName: "greek yogurt bowl",
            loggedAt: loggedAt,
            entryID: UUID(),
            components: [
                FoodMemoryComponentSummary(
                    normalizedName: "greek yogurt",
                    role: .protein,
                    observationCount: 1,
                    typicalCalories: 180,
                    typicalProteinGrams: 18,
                    typicalCarbsGrams: 8,
                    typicalFatGrams: 6
                )
            ]
        )
        secondMemory.status = .confirmed
        secondMemory.observationCount = 4

        context.insert(firstMemory)
        context.insert(secondMemory)
        try context.save()

        try service.recordOutcome(
            .dismissed,
            for: [firstMemory.id, secondMemory.id],
            at: loggedAt,
            modelContext: context
        )

        let refreshedMemories = try context.fetch(FetchDescriptor<FoodMemory>())
        let dismissedCounts = refreshedMemories.compactMap(\.suggestionStats?.timesDismissed)

        XCTAssertEqual(dismissedCounts.count, 2)
        XCTAssertTrue(dismissedCounts.allSatisfy { $0 == 1 })
        XCTAssertTrue(
            refreshedMemories.allSatisfy { $0.suggestionStats?.lastDismissedAt == loggedAt }
        )
    }

    private func component(
        _ name: String,
        role: FoodComponentRole,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> AcceptedFoodComponent {
        AcceptedFoodComponent(
            id: name,
            displayName: name.capitalized,
            normalizedName: FoodNormalizationService().normalizeFoodName(name),
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

    private func makeEntry(
        name: String,
        loggedAt: Date,
        calories: Int = 620,
        protein: Double = 42,
        carbs: Double = 58,
        fat: Double = 16,
        components: [AcceptedFoodComponent]
    ) -> FoodEntry {
        let normalizationService = FoodNormalizationService()
        let mealTimeBucket = normalizationService.mealTimeBucket(for: loggedAt)
        let entry = FoodEntry(
            name: name,
            mealType: mealType(for: mealTimeBucket).rawValue,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
        entry.loggedAt = loggedAt
        let snapshot = AcceptedFoodSnapshot(
            version: 1,
            source: .camera,
            kind: .meal,
            displayName: name,
            normalizedDisplayName: FoodNormalizationService().normalizeFoodName(name),
            nameAliases: FoodNormalizationService().aliasCandidates(for: name),
            mealLabel: FoodEntry.MealType.lunch.rawValue,
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
            loggedAt: loggedAt,
            mealTimeBucket: mealTimeBucket,
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: [],
            wasUserEdited: false
        )
        entry.setAcceptedSnapshot(snapshot)
        return entry
    }

    private func makeLegacyEntry(
        name: String,
        loggedAt: Date,
        input: FoodEntry.InputMethod
    ) -> FoodEntry {
        let entry = FoodEntry(
            name: name,
            mealType: FoodEntry.MealType.snack.rawValue,
            calories: 230,
            proteinGrams: 30,
            carbsGrams: 12,
            fatGrams: 5
        )
        entry.loggedAt = loggedAt
        entry.input = input
        entry.servingSize = "1 bottle"
        entry.ensureDisplayMetadata()
        return entry
    }

    private func makeMemory(
        name: String,
        normalizedName: String,
        loggedAt: Date,
        entryID: UUID,
        components: [FoodMemoryComponentSummary]
    ) -> FoodMemory {
        let normalizationService = FoodNormalizationService()
        let mealTimeBucket = normalizationService.mealTimeBucket(for: loggedAt)
        let hour = Calendar.current.component(.hour, from: loggedAt)
        let isWeekend = Calendar.current.isDateInWeekend(loggedAt)
        let memory = FoodMemory()
        memory.kind = .meal
        memory.status = .candidate
        memory.displayName = name
        memory.primaryNormalizedName = normalizedName
        memory.aliases = [
            FoodMemoryAlias(
                normalizedName: normalizedName,
                displayName: name,
                observationCount: 1,
                wasUserEdited: false
            )
        ]
        memory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: 620,
            medianProteinGrams: 42,
            medianCarbsGrams: 58,
            medianFatGrams: 16,
            medianFiberGrams: 5,
            medianSugarGrams: 4,
            lowerCaloriesBound: 620,
            upperCaloriesBound: 620,
            lowerProteinBound: 42,
            upperProteinBound: 42
        )
        memory.servingProfile = FoodMemoryServingProfile(
            commonServingText: "1 bowl",
            commonQuantity: nil,
            commonUnit: nil,
            quantityVariance: 0
        )
        memory.components = components
        memory.fingerprints = [
            FoodMemoryFingerprint(version: 1, type: .normalizedName, value: normalizedName),
            FoodMemoryFingerprint(version: 1, type: .roundedMacroSignature, value: "42-58-16-620"),
            FoodMemoryFingerprint(version: 1, type: .componentSet, value: "grilled chicken|white rice"),
            FoodMemoryFingerprint(version: 1, type: .componentRoleSet, value: "carb|protein"),
            FoodMemoryFingerprint(version: 1, type: .mealTimeBucket, value: mealTimeBucket.rawValue)
        ]
        var hourCounts = Array(repeating: 0, count: 24)
        hourCounts[hour] = 1
        memory.timeProfile = FoodMemoryTimeProfile(
            hourCounts: hourCounts,
            bucketCounts: [mealTimeBucket.rawValue: 1],
            weekdayCount: isWeekend ? 0 : 1,
            weekendCount: isWeekend ? 1 : 0
        )
        memory.representativeEntryIds = [entryID.uuidString]
        memory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: 0,
            proportionWithStructuredComponents: 1,
            distinctObservationDays: 1,
            repeatedTimeBucketScore: 1
        )
        memory.matchStats = FoodMemoryMatchStats(
            acceptedMatches: 0,
            rejectedMatches: 0,
            ambiguousMatches: 0,
            lastResolverVersion: 1
        )
        memory.observationCount = 1
        memory.confirmedReuseCount = 0
        memory.confidenceScore = 0
        memory.lastObservedAt = loggedAt
        return memory
    }

    private func mealType(for bucket: MealTimeBucket) -> FoodEntry.MealType {
        switch bucket {
        case .breakfast:
            return .breakfast
        case .lunch:
            return .lunch
        case .dinner:
            return .dinner
        case .lateNight, .snack:
            return .snack
        }
    }
}
