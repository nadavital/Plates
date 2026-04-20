import Foundation
import SwiftData

struct FoodMemoryMaintenanceResult: Sendable {
    let backfilledEntries: Int
    let resolvedEntries: Int
}

struct FoodMemoryShadowSummary: Sendable {
    let totalEntries: Int
    let trackedEntries: Int
    let pendingEntries: Int
    let matchedEntries: Int
    let candidateEntries: Int
    let rejectedEntries: Int
    let legacyEntriesWithoutSnapshot: Int
    let entriesWithStructuredComponents: Int
    let totalMemories: Int
    let confirmedMemories: Int
    let candidateMemories: Int
    let averageMatchConfidence: Double
    let averageMatchedConfidence: Double
}

typealias FoodMemoryCameraSuggestion = FoodSuggestion

struct FoodMemoryService {
    private let matcher = FoodMemoryMatcher()

    @MainActor
    func enqueueResolution(for entry: FoodEntry, modelContext: ModelContext) {
        if entry.acceptedSnapshot != nil {
            entry.foodMemoryNeedsResolution = true
            entry.foodMemoryResolutionState = .queued
            try? modelContext.save()
        }
    }

    @MainActor
    func backfillHistoricalEntries(limit: Int, modelContext: ModelContext) throws -> Int {
        guard limit > 0 else { return 0 }

        let descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        let candidates = try modelContext.fetch(descriptor)
        var backfilledEntries = 0

        for entry in candidates where backfilledEntries < limit {
            guard entry.acceptedSnapshot == nil, isEligibleForHistoricalBackfill(entry) else { continue }
            let snapshot = FoodSnapshotBuilder().buildAcceptedSnapshot(
                from: entry,
                source: acceptedSource(for: entry)
            )
            entry.setAcceptedSnapshot(snapshot, matchVersion: matcher.resolverVersion)
            backfilledEntries += 1
        }

        if backfilledEntries > 0 {
            try modelContext.save()
        }

        return backfilledEntries
    }

    @MainActor
    func resolvePendingEntries(limit: Int, modelContext: ModelContext) throws -> Int {
        guard limit > 0 else { return 0 }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.foodMemoryNeedsResolution == true },
            sortBy: [SortDescriptor(\FoodEntry.loggedAt)]
        )

        let entryIDs = try modelContext.fetch(descriptor)
            .prefix(limit)
            .map(\.id)
        guard !entryIDs.isEmpty else { return 0 }

        var workingMemories = try modelContext.fetch(FetchDescriptor<FoodMemory>())
        var resolvedEntries = 0

        for entryID in entryIDs {
            if try resolveEntry(
                id: entryID,
                workingMemories: &workingMemories,
                modelContext: modelContext
            ) {
                resolvedEntries += 1
            }
        }

        try modelContext.save()
        _ = try consolidateDuplicateMemories(modelContext: modelContext)
        return resolvedEntries
    }

    @MainActor
    func resolveEntry(id entryID: UUID, modelContext: ModelContext) throws -> Bool {
        var workingMemories = try modelContext.fetch(FetchDescriptor<FoodMemory>())
        let resolved = try resolveEntry(
            id: entryID,
            workingMemories: &workingMemories,
            modelContext: modelContext
        )
        guard resolved else { return false }

        try modelContext.save()
        _ = try consolidateDuplicateMemories(modelContext: modelContext)
        return true
    }

    @MainActor
    func consolidateDuplicateMemories(modelContext: ModelContext) throws -> Int {
        let memories = try modelContext.fetch(
            FetchDescriptor<FoodMemory>(
                sortBy: [SortDescriptor(\FoodMemory.updatedAt, order: .reverse)]
            )
        )
        guard memories.count > 1 else { return 0 }

        let entries = try modelContext.fetch(FetchDescriptor<FoodEntry>())
        return try consolidateDuplicateMemories(
            memories: memories,
            entries: entries,
            modelContext: modelContext
        )
    }

    @MainActor
    func consolidateDuplicateMemories(
        memoryIDs: [UUID],
        modelContext: ModelContext
    ) throws -> Int {
        let ids = Set(memoryIDs)
        guard ids.count > 1 else { return 0 }

        let memories = try modelContext.fetch(
            FetchDescriptor<FoodMemory>(
                sortBy: [SortDescriptor(\FoodMemory.updatedAt, order: .reverse)]
            )
        ).filter { ids.contains($0.id) }
        guard memories.count > 1 else { return 0 }

        let entries = try modelContext.fetch(FetchDescriptor<FoodEntry>())
        return try consolidateDuplicateMemories(
            memories: memories,
            entries: entries,
            modelContext: modelContext
        )
    }

    @MainActor
    func runMaintenance(
        backfillLimit: Int,
        resolveLimit: Int,
        modelContext: ModelContext
    ) throws -> FoodMemoryMaintenanceResult {
        let backfilledEntries = try backfillHistoricalEntries(limit: backfillLimit, modelContext: modelContext)
        let resolvedEntries = try resolvePendingEntries(limit: resolveLimit, modelContext: modelContext)
        return FoodMemoryMaintenanceResult(
            backfilledEntries: backfilledEntries,
            resolvedEntries: resolvedEntries
        )
    }

    @MainActor
    func shadowSummary(modelContext: ModelContext) throws -> FoodMemoryShadowSummary {
        let entries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)])
        )
        let memories = try modelContext.fetch(FetchDescriptor<FoodMemory>())

        let trackedEntries = entries.filter {
            $0.acceptedSnapshotData != nil || $0.foodMemoryResolutionState != .unresolved
        }
        let matchedEntries = trackedEntries.filter { $0.foodMemoryResolutionState == .matched }
        let averageMatchConfidence = trackedEntries.isEmpty
            ? 0
            : trackedEntries.map(\.foodMemoryMatchConfidence).reduce(0, +) / Double(trackedEntries.count)
        let averageMatchedConfidence = matchedEntries.isEmpty
            ? 0
            : matchedEntries.map(\.foodMemoryMatchConfidence).reduce(0, +) / Double(matchedEntries.count)

        return FoodMemoryShadowSummary(
            totalEntries: entries.count,
            trackedEntries: trackedEntries.count,
            pendingEntries: trackedEntries.filter { $0.foodMemoryNeedsResolution }.count,
            matchedEntries: matchedEntries.count,
            candidateEntries: trackedEntries.filter { $0.foodMemoryResolutionState == .createdCandidate }.count,
            rejectedEntries: trackedEntries.filter { $0.foodMemoryResolutionState == .rejected }.count,
            legacyEntriesWithoutSnapshot: entries.filter { $0.acceptedSnapshotData == nil && isEligibleForHistoricalBackfill($0) }.count,
            entriesWithStructuredComponents: trackedEntries.filter {
                $0.acceptedComponents.contains(where: { $0.source != .derived })
            }.count,
            totalMemories: memories.count,
            confirmedMemories: memories.filter { $0.status == .confirmed }.count,
            candidateMemories: memories.filter { $0.status == .candidate }.count,
            averageMatchConfidence: averageMatchConfidence,
            averageMatchedConfidence: averageMatchedConfidence
        )
    }

    @MainActor
    func cameraSuggestions(
        limit: Int,
        now: Date = .now,
        sessionId: UUID? = nil,
        modelContext: ModelContext
    ) throws -> [FoodMemoryCameraSuggestion] {
        try FoodSuggestionService().cameraSuggestions(
            limit: limit,
            now: now,
            sessionId: sessionId,
            modelContext: modelContext
        )
    }

    private func applyResolution(
        _ result: FoodMemoryMatchResult,
        to entry: FoodEntry,
        state: FoodMemoryResolutionState,
        memoryID: UUID? = nil
    ) {
        entry.foodMemoryNeedsResolution = false
        entry.foodMemoryResolutionState = state
        entry.foodMemoryMatchConfidence = result.confidence
        entry.foodMemoryMatchVersion = result.explanation.resolverVersion
        entry.foodMemoryResolvedAt = .now
        entry.foodMemoryResolutionExplanation = result.explanation
        if let memoryID {
            entry.foodMemoryIdString = memoryID.uuidString
        } else if let memoryId = result.memoryId {
            entry.foodMemoryIdString = memoryId.uuidString
        }
    }

    @MainActor
    private func resolveEntry(
        id entryID: UUID,
        workingMemories: inout [FoodMemory],
        modelContext: ModelContext
    ) throws -> Bool {
        let entryDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.id == entryID }
        )
        guard let entry = try modelContext.fetch(entryDescriptor).first else { return false }
        guard let snapshot = entry.acceptedSnapshot else {
            entry.foodMemoryNeedsResolution = false
            entry.foodMemoryResolutionState = .rejected
            return true
        }

        let index = FoodMemoryIndex(memories: workingMemories)
        let indexedCandidates = index.candidates(for: snapshot)
        let candidates = indexedCandidates.isEmpty ? workingMemories : indexedCandidates
        let result = matcher.match(snapshot: snapshot, candidates: candidates)

        switch result.outcome {
        case .matched:
            if let memory = workingMemories.first(where: { $0.id == result.memoryId }) {
                update(memory: memory, with: snapshot, entry: entry, confidence: result.confidence)
                applyResolution(result, to: entry, state: .matched)
            } else {
                let memory = createCandidateMemory(from: snapshot, entryID: entry.id, confidence: result.confidence)
                modelContext.insert(memory)
                workingMemories.append(memory)
                applyResolution(result, to: entry, state: .createdCandidate, memoryID: memory.id)
            }
        case .createCandidate, .reject:
            let memory = createCandidateMemory(from: snapshot, entryID: entry.id, confidence: result.confidence)
            modelContext.insert(memory)
            workingMemories.append(memory)
            applyResolution(result, to: entry, state: .createdCandidate, memoryID: memory.id)
        }

        return true
    }

    private func isEligibleForHistoricalBackfill(_ entry: FoodEntry) -> Bool {
        !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.calories >= 0
    }

    private func acceptedSource(for entry: FoodEntry) -> AcceptedFoodSource {
        switch entry.input {
        case .manual:
            return .manual
        case .camera:
            return .camera
        case .photo:
            return .photo
        case .description:
            return .description
        case .memorySuggestion:
            return .memorySuggestion
        case .chat:
            return .chat
        case .appIntent:
            return .appIntent
        }
    }

    private func createCandidateMemory(
        from snapshot: AcceptedFoodSnapshot,
        entryID: UUID,
        confidence: Double
    ) -> FoodMemory {
        let memory = FoodMemory()
        memory.kind = snapshot.kind
        memory.status = .candidate
        memory.displayName = snapshot.displayName
        memory.emoji = snapshot.emoji
        memory.primaryNormalizedName = snapshot.normalizedDisplayName
        memory.aliases = [
            FoodMemoryAlias(
                normalizedName: snapshot.normalizedDisplayName,
                displayName: snapshot.displayName,
                observationCount: 1,
                wasUserEdited: snapshot.wasUserEdited
            )
        ]
        memory.nutritionProfile = FoodMemoryNutritionProfile(
            medianCalories: snapshot.totalCalories,
            medianProteinGrams: snapshot.totalProteinGrams,
            medianCarbsGrams: snapshot.totalCarbsGrams,
            medianFatGrams: snapshot.totalFatGrams,
            medianFiberGrams: snapshot.totalFiberGrams,
            medianSugarGrams: snapshot.totalSugarGrams,
            lowerCaloriesBound: snapshot.totalCalories,
            upperCaloriesBound: snapshot.totalCalories,
            lowerProteinBound: snapshot.totalProteinGrams,
            upperProteinBound: snapshot.totalProteinGrams
        )
        memory.servingProfile = FoodMemoryServingProfile(
            commonServingText: snapshot.servingText,
            commonQuantity: snapshot.servingQuantity,
            commonUnit: snapshot.servingUnit,
            quantityVariance: 0
        )
        memory.components = snapshot.components.map {
            FoodMemoryComponentSummary(
                normalizedName: $0.normalizedName,
                role: $0.role,
                observationCount: 1,
                typicalCalories: $0.calories,
                typicalProteinGrams: $0.proteinGrams,
                typicalCarbsGrams: $0.carbsGrams,
                typicalFatGrams: $0.fatGrams
            )
        }
        memory.fingerprints = candidateFingerprints(from: snapshot)
        memory.representativeEntryIds = [entryID.uuidString]
        let timeProfile = buildTimeProfile(from: snapshot)
        memory.timeProfile = timeProfile
        memory.qualitySignals = FoodMemoryQualitySignals(
            proportionUserEdited: snapshot.wasUserEdited ? 1 : 0,
            proportionWithStructuredComponents: snapshot.components.contains(where: { $0.source != .derived }) ? 1 : 0,
            distinctObservationDays: 1,
            repeatedTimeBucketScore: timeConsistencyScore(for: timeProfile)
        )
        memory.repeatPattern = initialRepeatPattern(for: snapshot)
        memory.matchStats = FoodMemoryMatchStats(
            acceptedMatches: 0,
            rejectedMatches: 0,
            ambiguousMatches: 0,
            lastResolverVersion: matcher.resolverVersion
        )
        memory.observationCount = 1
        memory.confirmedReuseCount = 0
        memory.confidenceScore = confidence
        memory.lastObservedAt = snapshot.loggedAt
        return memory
    }

    private func candidateFingerprints(from snapshot: AcceptedFoodSnapshot) -> [FoodMemoryFingerprint] {
        let macroSignature = [
            String(Int(snapshot.totalProteinGrams.rounded())),
            String(Int(snapshot.totalCarbsGrams.rounded())),
            String(Int(snapshot.totalFatGrams.rounded())),
            String(snapshot.totalCalories)
        ].joined(separator: "-")
        let coarseMacroBucket = [
            "cal:\(Int((Double(snapshot.totalCalories) / 100).rounded() * 100))",
            "p:\(Int((snapshot.totalProteinGrams / 10).rounded() * 10))",
            "c:\(Int((snapshot.totalCarbsGrams / 10).rounded() * 10))",
            "f:\(Int((snapshot.totalFatGrams / 5).rounded() * 5))"
        ].joined(separator: "|")
        let componentSet = snapshot.components.map(\.normalizedName).sorted().joined(separator: "|")
        let roleSet = snapshot.components.map(\.role.rawValue).sorted().joined(separator: "|")
        let servingSignature = servingSignature(for: snapshot)

        let nameFingerprints = snapshot.nameAliases.map {
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .normalizedName, value: $0)
        }

        return nameFingerprints + [
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .roundedMacroSignature, value: macroSignature),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .coarseMacroBucket, value: coarseMacroBucket),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .componentSet, value: componentSet),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .componentRoleSet, value: roleSet),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .servingSignature, value: servingSignature),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .mealTimeBucket, value: snapshot.mealTimeBucket.rawValue)
        ].filter { !$0.value.isEmpty }
    }

    private func update(
        memory: FoodMemory,
        with snapshot: AcceptedFoodSnapshot,
        entry: FoodEntry,
        confidence: Double
    ) {
        let previousObservationCount = memory.observationCount
        let previousLastObservedAt = memory.lastObservedAt
        memory.observationCount += 1
        memory.confirmedReuseCount += 1
        memory.updatedAt = .now
        memory.lastObservedAt = max(memory.lastObservedAt, snapshot.loggedAt)
        memory.confidenceScore = max(memory.confidenceScore, confidence)
        if let emoji = snapshot.emoji, !emoji.isEmpty {
            memory.emoji = emoji
        }
        memory.aliases = mergedAliases(memory.aliases, snapshot: snapshot)
        memory.nutritionProfile = updatedNutritionProfile(
            existing: memory.nutritionProfile,
            snapshot: snapshot,
            previousObservationCount: previousObservationCount
        )
        memory.servingProfile = updatedServingProfile(memory.servingProfile, snapshot: snapshot)
        memory.timeProfile = updatedTimeProfile(memory.timeProfile, snapshot: snapshot)
        memory.components = mergedComponents(memory.components, snapshot: snapshot, previousObservationCount: previousObservationCount)
        memory.fingerprints = buildFingerprints(from: snapshot, existing: memory.fingerprints)
        memory.representativeEntryIds = mergedRepresentativeEntries(memory.representativeEntryIds, newEntryID: entry.id.uuidString)
        memory.qualitySignals = updatedQualitySignals(
            existing: memory.qualitySignals,
            snapshot: snapshot,
            previousObservationCount: previousObservationCount,
            previousLastObservedAt: previousLastObservedAt,
            timeProfile: memory.timeProfile
        )
        memory.repeatPattern = updatedRepeatPattern(
            existing: memory.repeatPattern,
            snapshot: snapshot,
            previousObservationCount: previousObservationCount,
            previousLastObservedAt: previousLastObservedAt
        )

        let existingStats = memory.matchStats ?? FoodMemoryMatchStats(
            acceptedMatches: 0,
            rejectedMatches: 0,
            ambiguousMatches: 0,
            lastResolverVersion: matcher.resolverVersion
        )
        memory.matchStats = FoodMemoryMatchStats(
            acceptedMatches: existingStats.acceptedMatches + 1,
            rejectedMatches: existingStats.rejectedMatches,
            ambiguousMatches: existingStats.ambiguousMatches,
            lastResolverVersion: matcher.resolverVersion
        )

        if memory.observationCount >= 3 || memory.confirmedReuseCount >= 2 {
            memory.status = .confirmed
        }
    }

    private func isHigherPriorityMemory(_ lhs: FoodMemory, _ rhs: FoodMemory) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status == .confirmed
        }

        let lhsAcceptedSuggestions = lhs.suggestionStats?.timesAccepted ?? 0
        let rhsAcceptedSuggestions = rhs.suggestionStats?.timesAccepted ?? 0
        if lhsAcceptedSuggestions != rhsAcceptedSuggestions {
            return lhsAcceptedSuggestions > rhsAcceptedSuggestions
        }

        if lhs.observationCount != rhs.observationCount {
            return lhs.observationCount > rhs.observationCount
        }

        if lhs.confirmedReuseCount != rhs.confirmedReuseCount {
            return lhs.confirmedReuseCount > rhs.confirmedReuseCount
        }

        if lhs.confidenceScore != rhs.confidenceScore {
            return lhs.confidenceScore > rhs.confidenceScore
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func consolidateDuplicateMemories(
        memories: [FoodMemory],
        entries: [FoodEntry],
        modelContext: ModelContext
    ) throws -> Int {
        let prioritizedMemories = memories
            .filter { $0.status != .retired }
            .sorted(by: isHigherPriorityMemory)

        var mergedMemoryIDs = Set<UUID>()
        var mergedCount = 0

        for (index, primary) in prioritizedMemories.enumerated() {
            guard !mergedMemoryIDs.contains(primary.id) else { continue }

            for candidate in prioritizedMemories.suffix(from: index + 1) {
                guard !mergedMemoryIDs.contains(candidate.id) else { continue }
                guard matcher.representsSameHabit(primary, candidate) else { continue }

                merge(memory: candidate, into: primary, entries: entries)
                mergedMemoryIDs.insert(candidate.id)
                mergedCount += 1
            }
        }

        guard mergedCount > 0 else { return 0 }

        for memory in memories where mergedMemoryIDs.contains(memory.id) {
            modelContext.delete(memory)
        }

        try modelContext.save()
        return mergedCount
    }

    private func merge(
        memory source: FoodMemory,
        into target: FoodMemory,
        entries: [FoodEntry]
    ) {
        let targetObservationCount = max(target.observationCount, 1)
        let sourceObservationCount = max(source.observationCount, 1)
        let totalObservationCount = targetObservationCount + sourceObservationCount

        let mergedAliases = mergedAliases(target.aliases, with: source.aliases)
        let mergedTimeProfile = mergedTimeProfile(target.timeProfile, source.timeProfile)
        let mergedRepeatPattern = mergedRepeatPattern(
            target.repeatPattern,
            targetObservationCount: targetObservationCount,
            source.repeatPattern,
            sourceObservationCount: sourceObservationCount
        )

        target.status = mergedStatus(target.status, source.status, totalObservationCount: totalObservationCount, totalReuseCount: target.confirmedReuseCount + source.confirmedReuseCount)
        target.displayName = preferredDisplayName(from: mergedAliases, fallback: target.displayName, secondaryFallback: source.displayName)
        target.primaryNormalizedName = preferredPrimaryNormalizedName(from: mergedAliases, fallback: target.primaryNormalizedName, secondaryFallback: source.primaryNormalizedName)
        target.emoji = preferredEmoji(primary: target.emoji, secondary: source.emoji)
        target.aliases = mergedAliases
        target.nutritionProfile = mergedNutritionProfile(
            target.nutritionProfile,
            targetObservationCount: targetObservationCount,
            source.nutritionProfile,
            sourceObservationCount: sourceObservationCount
        )
        target.servingProfile = mergedServingProfile(
            target.servingProfile,
            targetObservationCount: targetObservationCount,
            source.servingProfile,
            sourceObservationCount: sourceObservationCount
        )
        target.timeProfile = mergedTimeProfile
        target.components = mergedComponents(target.components, with: source.components)
        target.fingerprints = mergedFingerprints(target.fingerprints, with: source.fingerprints)
        target.representativeEntryIds = mergedRepresentativeEntryIDs(target.representativeEntryIds, source.representativeEntryIds)
        target.qualitySignals = mergedQualitySignals(
            target.qualitySignals,
            targetObservationCount: targetObservationCount,
            source.qualitySignals,
            sourceObservationCount: sourceObservationCount,
            timeProfile: mergedTimeProfile,
            totalObservationCount: totalObservationCount
        )
        target.suggestionStats = mergedSuggestionStats(target.suggestionStats, source.suggestionStats)
        target.repeatPattern = mergedRepeatPattern
        target.matchStats = mergedMatchStats(target.matchStats, source.matchStats)
        target.observationCount = totalObservationCount
        target.confirmedReuseCount += source.confirmedReuseCount
        target.confidenceScore = max(target.confidenceScore, source.confidenceScore)
        target.createdAt = min(target.createdAt, source.createdAt)
        target.updatedAt = .now
        target.lastObservedAt = max(target.lastObservedAt, source.lastObservedAt)

        rewireEntriesLinked(to: source.id, into: target.id, entries: entries)
    }

    private func buildNutritionProfile(from snapshot: AcceptedFoodSnapshot) -> FoodMemoryNutritionProfile {
        FoodMemoryNutritionProfile(
            medianCalories: snapshot.totalCalories,
            medianProteinGrams: snapshot.totalProteinGrams,
            medianCarbsGrams: snapshot.totalCarbsGrams,
            medianFatGrams: snapshot.totalFatGrams,
            medianFiberGrams: snapshot.totalFiberGrams,
            medianSugarGrams: snapshot.totalSugarGrams,
            lowerCaloriesBound: snapshot.totalCalories,
            upperCaloriesBound: snapshot.totalCalories,
            lowerProteinBound: snapshot.totalProteinGrams,
            upperProteinBound: snapshot.totalProteinGrams
        )
    }

    private func updatedNutritionProfile(
        existing: FoodMemoryNutritionProfile?,
        snapshot: AcceptedFoodSnapshot,
        previousObservationCount: Int
    ) -> FoodMemoryNutritionProfile {
        guard let existing else { return buildNutritionProfile(from: snapshot) }

        let count = max(previousObservationCount, 1)
        let blendedCalories = blended(existing: Double(existing.medianCalories), observed: Double(snapshot.totalCalories), count: count)
        let blendedProtein = blended(existing: existing.medianProteinGrams, observed: snapshot.totalProteinGrams, count: count)
        let blendedCarbs = blended(existing: existing.medianCarbsGrams, observed: snapshot.totalCarbsGrams, count: count)
        let blendedFat = blended(existing: existing.medianFatGrams, observed: snapshot.totalFatGrams, count: count)

        return FoodMemoryNutritionProfile(
            medianCalories: Int(blendedCalories.rounded()),
            medianProteinGrams: blendedProtein,
            medianCarbsGrams: blendedCarbs,
            medianFatGrams: blendedFat,
            medianFiberGrams: blendedOptional(existing.medianFiberGrams, snapshot.totalFiberGrams, count: count),
            medianSugarGrams: blendedOptional(existing.medianSugarGrams, snapshot.totalSugarGrams, count: count),
            lowerCaloriesBound: min(existing.lowerCaloriesBound, snapshot.totalCalories),
            upperCaloriesBound: max(existing.upperCaloriesBound, snapshot.totalCalories),
            lowerProteinBound: min(existing.lowerProteinBound, snapshot.totalProteinGrams),
            upperProteinBound: max(existing.upperProteinBound, snapshot.totalProteinGrams)
        )
    }

    private func buildTimeProfile(from snapshot: AcceptedFoodSnapshot) -> FoodMemoryTimeProfile {
        let hour = Calendar.current.component(.hour, from: snapshot.loggedAt)
        var hourCounts = Array(repeating: 0, count: 24)
        if hourCounts.indices.contains(hour) {
            hourCounts[hour] = 1
        }

        var bucketCounts: [String: Int] = [:]
        bucketCounts[snapshot.mealTimeBucket.rawValue] = 1

        let isWeekend = Calendar.current.isDateInWeekend(snapshot.loggedAt)
        return FoodMemoryTimeProfile(
            hourCounts: hourCounts,
            bucketCounts: bucketCounts,
            weekdayCount: isWeekend ? 0 : 1,
            weekendCount: isWeekend ? 1 : 0
        )
    }

    private func updatedTimeProfile(
        _ existing: FoodMemoryTimeProfile?,
        snapshot: AcceptedFoodSnapshot
    ) -> FoodMemoryTimeProfile {
        guard let existing else { return buildTimeProfile(from: snapshot) }

        var hourCounts = existing.hourCounts
        let hour = Calendar.current.component(.hour, from: snapshot.loggedAt)
        if hourCounts.indices.contains(hour) {
            hourCounts[hour] += 1
        }

        var bucketCounts = existing.bucketCounts
        bucketCounts[snapshot.mealTimeBucket.rawValue, default: 0] += 1

        let isWeekend = Calendar.current.isDateInWeekend(snapshot.loggedAt)
        return FoodMemoryTimeProfile(
            hourCounts: hourCounts,
            bucketCounts: bucketCounts,
            weekdayCount: existing.weekdayCount + (isWeekend ? 0 : 1),
            weekendCount: existing.weekendCount + (isWeekend ? 1 : 0)
        )
    }

    private func dominantBucket(in profile: FoodMemoryTimeProfile) -> MealTimeBucket? {
        profile.bucketCounts
            .max { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.key > rhs.key
            }
            .flatMap { MealTimeBucket(rawValue: $0.key) }
    }

    private func dominantHourWindowSupport(
        in profile: FoodMemoryTimeProfile,
        totalObservations: Int
    ) -> Double {
        guard !profile.hourCounts.isEmpty else { return 0 }
        var bestCount = 0
        for hour in 0..<24 {
            let windowCount = [-1, 0, 1].reduce(0) { partialResult, offset in
                partialResult + profile.hourCounts[(hour + offset + 24) % 24]
            }
            bestCount = max(bestCount, windowCount)
        }
        return Double(bestCount) / Double(totalObservations)
    }

    private func timeConsistencyScore(for profile: FoodMemoryTimeProfile?) -> Double {
        guard let profile else { return 0.5 }
        let total = max(1, profile.hourCounts.reduce(0, +))
        let dominantBucketShare = dominantBucket(in: profile).flatMap {
            profile.bucketCounts[$0.rawValue]
        }.map { Double($0) / Double(total) } ?? 0
        let dominantHourShare = dominantHourWindowSupport(in: profile, totalObservations: total)
        return min(max((dominantBucketShare * 0.55) + (dominantHourShare * 0.45), 0), 1)
    }

    private func updatedServingProfile(
        _ existing: FoodMemoryServingProfile?,
        snapshot: AcceptedFoodSnapshot
    ) -> FoodMemoryServingProfile {
        let previousQuantity = existing?.commonQuantity
        let nextQuantity = snapshot.servingQuantity ?? previousQuantity
        let quantityVariance: Double?
        if let previousQuantity, let snapshotQuantity = snapshot.servingQuantity {
            quantityVariance = abs(snapshotQuantity - previousQuantity)
        } else {
            quantityVariance = existing?.quantityVariance ?? 0
        }

        return FoodMemoryServingProfile(
            commonServingText: snapshot.servingText ?? existing?.commonServingText,
            commonQuantity: nextQuantity,
            commonUnit: snapshot.servingUnit ?? existing?.commonUnit,
            quantityVariance: quantityVariance
        )
    }

    private func mergedComponents(
        _ existing: [FoodMemoryComponentSummary],
        snapshot: AcceptedFoodSnapshot,
        previousObservationCount: Int
    ) -> [FoodMemoryComponentSummary] {
        var byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.normalizedName, $0) })

        for component in snapshot.components {
            if let prior = byName[component.normalizedName] {
                let newCount = prior.observationCount + 1
                byName[component.normalizedName] = FoodMemoryComponentSummary(
                    normalizedName: prior.normalizedName,
                    role: component.role == .other ? prior.role : component.role,
                    observationCount: newCount,
                    typicalCalories: Int(blended(existing: Double(prior.typicalCalories), observed: Double(component.calories), count: prior.observationCount).rounded()),
                    typicalProteinGrams: blended(existing: prior.typicalProteinGrams, observed: component.proteinGrams, count: prior.observationCount),
                    typicalCarbsGrams: blended(existing: prior.typicalCarbsGrams, observed: component.carbsGrams, count: prior.observationCount),
                    typicalFatGrams: blended(existing: prior.typicalFatGrams, observed: component.fatGrams, count: prior.observationCount)
                )
            } else {
                byName[component.normalizedName] = FoodMemoryComponentSummary(
                    normalizedName: component.normalizedName,
                    role: component.role,
                    observationCount: max(previousObservationCount > 0 ? 1 : 1, 1),
                    typicalCalories: component.calories,
                    typicalProteinGrams: component.proteinGrams,
                    typicalCarbsGrams: component.carbsGrams,
                    typicalFatGrams: component.fatGrams
                )
            }
        }

        return byName.values.sorted { lhs, rhs in
            if lhs.observationCount != rhs.observationCount {
                return lhs.observationCount > rhs.observationCount
            }
            return lhs.normalizedName < rhs.normalizedName
        }
    }

    private func buildFingerprints(
        from snapshot: AcceptedFoodSnapshot,
        existing: [FoodMemoryFingerprint] = []
    ) -> [FoodMemoryFingerprint] {
        var fingerprints = Dictionary(uniqueKeysWithValues: existing.map { ("\($0.type.rawValue)|\($0.value)", $0) })

        let componentSet = snapshot.components.map(\.normalizedName).sorted().joined(separator: "|")
        let roleSet = snapshot.components.map(\.role.rawValue).sorted().joined(separator: "|")
        let macroSignature = [
            String(Int(snapshot.totalProteinGrams.rounded())),
            String(Int(snapshot.totalCarbsGrams.rounded())),
            String(Int(snapshot.totalFatGrams.rounded())),
            String(snapshot.totalCalories)
        ].joined(separator: "-")
        let coarseMacroBucket = [
            "cal:\(Int((Double(snapshot.totalCalories) / 100).rounded() * 100))",
            "p:\(Int((snapshot.totalProteinGrams / 10).rounded() * 10))",
            "c:\(Int((snapshot.totalCarbsGrams / 10).rounded() * 10))",
            "f:\(Int((snapshot.totalFatGrams / 5).rounded() * 5))"
        ].joined(separator: "|")
        let servingSignature = servingSignature(for: snapshot)

        let newFingerprints: [FoodMemoryFingerprint] = snapshot.nameAliases.map {
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .normalizedName, value: $0)
        } + [
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .roundedMacroSignature, value: macroSignature),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .coarseMacroBucket, value: coarseMacroBucket),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .componentSet, value: componentSet),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .componentRoleSet, value: roleSet),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .servingSignature, value: servingSignature),
            FoodMemoryFingerprint(version: matcher.resolverVersion, type: .mealTimeBucket, value: snapshot.mealTimeBucket.rawValue)
        ].filter { !$0.value.isEmpty }

        for fingerprint in newFingerprints {
            fingerprints["\(fingerprint.type.rawValue)|\(fingerprint.value)"] = fingerprint
        }

        return Array(fingerprints.values)
    }

    private func mergedAliases(
        _ existing: [FoodMemoryAlias],
        snapshot: AcceptedFoodSnapshot
    ) -> [FoodMemoryAlias] {
        var aliasesByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.normalizedName, $0) })
        let alias = FoodMemoryAlias(
            normalizedName: snapshot.normalizedDisplayName,
            displayName: snapshot.displayName,
            observationCount: 1,
            wasUserEdited: snapshot.wasUserEdited
        )

        if let prior = aliasesByName[alias.normalizedName] {
            aliasesByName[alias.normalizedName] = FoodMemoryAlias(
                normalizedName: prior.normalizedName,
                displayName: snapshot.wasUserEdited ? alias.displayName : prior.displayName,
                observationCount: prior.observationCount + 1,
                wasUserEdited: prior.wasUserEdited || alias.wasUserEdited
            )
        } else {
            aliasesByName[alias.normalizedName] = alias
        }

        return aliasesByName.values.sorted { lhs, rhs in
            if lhs.observationCount != rhs.observationCount {
                return lhs.observationCount > rhs.observationCount
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private func mergedRepresentativeEntries(_ existing: [String], newEntryID: String) -> [String] {
        var ids = existing
        if !ids.contains(newEntryID) {
            ids.append(newEntryID)
        }
        return Array(ids.suffix(8))
    }

    private func updatedQualitySignals(
        existing: FoodMemoryQualitySignals?,
        snapshot: AcceptedFoodSnapshot,
        previousObservationCount: Int,
        previousLastObservedAt: Date,
        timeProfile: FoodMemoryTimeProfile?
    ) -> FoodMemoryQualitySignals {
        let count = max(previousObservationCount, 1)
        let prior = existing ?? FoodMemoryQualitySignals(
            proportionUserEdited: snapshot.wasUserEdited ? 1 : 0,
            proportionWithStructuredComponents: snapshot.components.contains(where: { $0.source != .derived }) ? 1 : 0,
            distinctObservationDays: 1,
            repeatedTimeBucketScore: 1
        )

        return FoodMemoryQualitySignals(
            proportionUserEdited: blended(
                existing: prior.proportionUserEdited,
                observed: snapshot.wasUserEdited ? 1 : 0,
                count: count
            ),
            proportionWithStructuredComponents: blended(
                existing: prior.proportionWithStructuredComponents,
                observed: snapshot.components.contains(where: { $0.source != .derived }) ? 1 : 0,
                count: count
            ),
            distinctObservationDays: prior.distinctObservationDays + (
                Calendar.current.isDate(snapshot.loggedAt, inSameDayAs: previousLastObservedAt) ? 0 : 1
            ),
            repeatedTimeBucketScore: timeConsistencyScore(for: timeProfile)
        )
    }

    private func initialRepeatPattern(for snapshot: AcceptedFoodSnapshot) -> FoodMemoryRepeatPattern {
        let dayAnchor = Calendar.current.startOfDay(for: snapshot.loggedAt)
        return FoodMemoryRepeatPattern(
            distinctConsumptionDays: 1,
            daysWithMultipleUses: 0,
            maxUsesInDay: 1,
            averageUsesPerDay: 1,
            averageRepeatGapMinutes: nil,
            repeatGapObservationCount: 0,
            currentDayUseCount: 1,
            currentDayAnchor: dayAnchor,
            lastConsumptionAt: snapshot.loggedAt
        )
    }

    private func updatedRepeatPattern(
        existing: FoodMemoryRepeatPattern?,
        snapshot: AcceptedFoodSnapshot,
        previousObservationCount: Int,
        previousLastObservedAt: Date
    ) -> FoodMemoryRepeatPattern {
        guard let existing else {
            return initialRepeatPattern(for: snapshot)
        }

        let calendar = Calendar.current
        let snapshotDay = calendar.startOfDay(for: snapshot.loggedAt)
        let priorDay = existing.currentDayAnchor
        let priorDayUseCount = existing.currentDayUseCount
        let sameDayObservation = calendar.isDate(snapshotDay, inSameDayAs: priorDay)

        let distinctConsumptionDays = existing.distinctConsumptionDays + (sameDayObservation ? 0 : 1)
        let currentDayUseCount = sameDayObservation ? (priorDayUseCount + 1) : 1
        let daysWithMultipleUses = existing.daysWithMultipleUses + (sameDayObservation && priorDayUseCount == 1 ? 1 : 0)
        let maxUsesInDay = max(existing.maxUsesInDay, currentDayUseCount)

        let averageRepeatGapMinutes: Double?
        let repeatGapObservationCount: Int
        if sameDayObservation {
            let observedGapMinutes = snapshot.loggedAt.timeIntervalSince(existing.lastConsumptionAt) / 60
            if let priorGap = existing.averageRepeatGapMinutes {
                averageRepeatGapMinutes = blended(
                    existing: priorGap,
                    observed: observedGapMinutes,
                    count: max(existing.repeatGapObservationCount, 1)
                )
            } else {
                averageRepeatGapMinutes = observedGapMinutes
            }
            repeatGapObservationCount = existing.repeatGapObservationCount + 1
        } else {
            averageRepeatGapMinutes = existing.averageRepeatGapMinutes
            repeatGapObservationCount = existing.repeatGapObservationCount
        }

        let totalObservations = Double(previousObservationCount + 1)
        let averageUsesPerDay = totalObservations / Double(max(distinctConsumptionDays, 1))

        return FoodMemoryRepeatPattern(
            distinctConsumptionDays: distinctConsumptionDays,
            daysWithMultipleUses: daysWithMultipleUses,
            maxUsesInDay: maxUsesInDay,
            averageUsesPerDay: averageUsesPerDay,
            averageRepeatGapMinutes: averageRepeatGapMinutes,
            repeatGapObservationCount: repeatGapObservationCount,
            currentDayUseCount: currentDayUseCount,
            currentDayAnchor: sameDayObservation ? priorDay : snapshotDay,
            lastConsumptionAt: max(max(existing.lastConsumptionAt, previousLastObservedAt), snapshot.loggedAt)
        )
    }

    private func mergedStatus(
        _ lhs: FoodMemoryStatus,
        _ rhs: FoodMemoryStatus,
        totalObservationCount: Int,
        totalReuseCount: Int
    ) -> FoodMemoryStatus {
        if lhs == .confirmed || rhs == .confirmed || totalObservationCount >= 3 || totalReuseCount >= 2 {
            return .confirmed
        }
        return .candidate
    }

    private func mergedNutritionProfile(
        _ lhs: FoodMemoryNutritionProfile?,
        targetObservationCount: Int,
        _ rhs: FoodMemoryNutritionProfile?,
        sourceObservationCount: Int
    ) -> FoodMemoryNutritionProfile? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return FoodMemoryNutritionProfile(
                medianCalories: Int(weightedAverage(Double(lhs.medianCalories), weight: targetObservationCount, Double(rhs.medianCalories), weight: sourceObservationCount).rounded()),
                medianProteinGrams: weightedAverage(lhs.medianProteinGrams, weight: targetObservationCount, rhs.medianProteinGrams, weight: sourceObservationCount),
                medianCarbsGrams: weightedAverage(lhs.medianCarbsGrams, weight: targetObservationCount, rhs.medianCarbsGrams, weight: sourceObservationCount),
                medianFatGrams: weightedAverage(lhs.medianFatGrams, weight: targetObservationCount, rhs.medianFatGrams, weight: sourceObservationCount),
                medianFiberGrams: weightedAverageOptional(lhs.medianFiberGrams, weight: targetObservationCount, rhs.medianFiberGrams, weight: sourceObservationCount),
                medianSugarGrams: weightedAverageOptional(lhs.medianSugarGrams, weight: targetObservationCount, rhs.medianSugarGrams, weight: sourceObservationCount),
                lowerCaloriesBound: min(lhs.lowerCaloriesBound, rhs.lowerCaloriesBound),
                upperCaloriesBound: max(lhs.upperCaloriesBound, rhs.upperCaloriesBound),
                lowerProteinBound: min(lhs.lowerProteinBound, rhs.lowerProteinBound),
                upperProteinBound: max(lhs.upperProteinBound, rhs.upperProteinBound)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedServingProfile(
        _ lhs: FoodMemoryServingProfile?,
        targetObservationCount: Int,
        _ rhs: FoodMemoryServingProfile?,
        sourceObservationCount: Int
    ) -> FoodMemoryServingProfile? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let targetWins = targetObservationCount >= sourceObservationCount
            return FoodMemoryServingProfile(
                commonServingText: preferredString(lhs.commonServingText, rhs.commonServingText, preferFirst: targetWins),
                commonQuantity: weightedAverageOptional(lhs.commonQuantity, weight: targetObservationCount, rhs.commonQuantity, weight: sourceObservationCount),
                commonUnit: preferredString(lhs.commonUnit, rhs.commonUnit, preferFirst: targetWins),
                quantityVariance: max(lhs.quantityVariance ?? 0, rhs.quantityVariance ?? 0)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedTimeProfile(
        _ lhs: FoodMemoryTimeProfile?,
        _ rhs: FoodMemoryTimeProfile?
    ) -> FoodMemoryTimeProfile? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let hourCounts = zip(lhs.hourCounts, rhs.hourCounts).map(+)
            var bucketCounts = lhs.bucketCounts
            for (bucket, count) in rhs.bucketCounts {
                bucketCounts[bucket, default: 0] += count
            }
            return FoodMemoryTimeProfile(
                hourCounts: hourCounts,
                bucketCounts: bucketCounts,
                weekdayCount: lhs.weekdayCount + rhs.weekdayCount,
                weekendCount: lhs.weekendCount + rhs.weekendCount
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedComponents(
        _ lhs: [FoodMemoryComponentSummary],
        with rhs: [FoodMemoryComponentSummary]
    ) -> [FoodMemoryComponentSummary] {
        var componentsByName = Dictionary(uniqueKeysWithValues: lhs.map { ($0.normalizedName, $0) })

        for component in rhs {
            if let prior = componentsByName[component.normalizedName] {
                let totalObservationCount = prior.observationCount + component.observationCount
                let preferredRole = prior.observationCount >= component.observationCount ? prior.role : component.role
                componentsByName[component.normalizedName] = FoodMemoryComponentSummary(
                    normalizedName: prior.normalizedName,
                    role: preferredRole == .other ? component.role : preferredRole,
                    observationCount: totalObservationCount,
                    typicalCalories: Int(weightedAverage(Double(prior.typicalCalories), weight: prior.observationCount, Double(component.typicalCalories), weight: component.observationCount).rounded()),
                    typicalProteinGrams: weightedAverage(prior.typicalProteinGrams, weight: prior.observationCount, component.typicalProteinGrams, weight: component.observationCount),
                    typicalCarbsGrams: weightedAverage(prior.typicalCarbsGrams, weight: prior.observationCount, component.typicalCarbsGrams, weight: component.observationCount),
                    typicalFatGrams: weightedAverage(prior.typicalFatGrams, weight: prior.observationCount, component.typicalFatGrams, weight: component.observationCount)
                )
            } else {
                componentsByName[component.normalizedName] = component
            }
        }

        return componentsByName.values.sorted { lhs, rhs in
            if lhs.observationCount != rhs.observationCount {
                return lhs.observationCount > rhs.observationCount
            }
            return lhs.normalizedName < rhs.normalizedName
        }
    }

    private func mergedFingerprints(
        _ lhs: [FoodMemoryFingerprint],
        with rhs: [FoodMemoryFingerprint]
    ) -> [FoodMemoryFingerprint] {
        var fingerprints = Dictionary(uniqueKeysWithValues: lhs.map { ("\($0.type.rawValue)|\($0.value)", $0) })
        for fingerprint in rhs {
            fingerprints["\(fingerprint.type.rawValue)|\(fingerprint.value)"] = fingerprint
        }
        return Array(fingerprints.values)
    }

    private func mergedAliases(
        _ lhs: [FoodMemoryAlias],
        with rhs: [FoodMemoryAlias]
    ) -> [FoodMemoryAlias] {
        var aliasesByName = Dictionary(uniqueKeysWithValues: lhs.map { ($0.normalizedName, $0) })

        for alias in rhs {
            if let prior = aliasesByName[alias.normalizedName] {
                let mergedObservationCount = prior.observationCount + alias.observationCount
                let preferredDisplayName: String
                if alias.wasUserEdited && !prior.wasUserEdited {
                    preferredDisplayName = alias.displayName
                } else if prior.wasUserEdited && !alias.wasUserEdited {
                    preferredDisplayName = prior.displayName
                } else if alias.observationCount > prior.observationCount {
                    preferredDisplayName = alias.displayName
                } else {
                    preferredDisplayName = prior.displayName
                }

                aliasesByName[alias.normalizedName] = FoodMemoryAlias(
                    normalizedName: prior.normalizedName,
                    displayName: preferredDisplayName,
                    observationCount: mergedObservationCount,
                    wasUserEdited: prior.wasUserEdited || alias.wasUserEdited
                )
            } else {
                aliasesByName[alias.normalizedName] = alias
            }
        }

        return aliasesByName.values.sorted { lhs, rhs in
            if lhs.wasUserEdited != rhs.wasUserEdited {
                return lhs.wasUserEdited && !rhs.wasUserEdited
            }
            if lhs.observationCount != rhs.observationCount {
                return lhs.observationCount > rhs.observationCount
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private func mergedRepresentativeEntryIDs(
        _ lhs: [String],
        _ rhs: [String]
    ) -> [String] {
        var ids = lhs
        for id in rhs where !ids.contains(id) {
            ids.append(id)
        }
        return Array(ids.suffix(8))
    }

    private func mergedQualitySignals(
        _ lhs: FoodMemoryQualitySignals?,
        targetObservationCount: Int,
        _ rhs: FoodMemoryQualitySignals?,
        sourceObservationCount: Int,
        timeProfile: FoodMemoryTimeProfile?,
        totalObservationCount: Int
    ) -> FoodMemoryQualitySignals? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return FoodMemoryQualitySignals(
                proportionUserEdited: weightedAverage(lhs.proportionUserEdited, weight: targetObservationCount, rhs.proportionUserEdited, weight: sourceObservationCount),
                proportionWithStructuredComponents: weightedAverage(lhs.proportionWithStructuredComponents, weight: targetObservationCount, rhs.proportionWithStructuredComponents, weight: sourceObservationCount),
                distinctObservationDays: min(lhs.distinctObservationDays + rhs.distinctObservationDays, max(totalObservationCount, 1)),
                repeatedTimeBucketScore: timeConsistencyScore(for: timeProfile)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedSuggestionStats(
        _ lhs: FoodMemorySuggestionStats?,
        _ rhs: FoodMemorySuggestionStats?
    ) -> FoodMemorySuggestionStats? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return FoodMemorySuggestionStats(
                timesShown: lhs.timesShown + rhs.timesShown,
                timesTapped: lhs.timesTapped + rhs.timesTapped,
                timesAccepted: lhs.timesAccepted + rhs.timesAccepted,
                timesDismissed: lhs.timesDismissed + rhs.timesDismissed,
                timesRefined: lhs.timesRefined + rhs.timesRefined,
                lastShownAt: latestDate(lhs.lastShownAt, rhs.lastShownAt),
                lastTappedAt: latestDate(lhs.lastTappedAt, rhs.lastTappedAt),
                lastAcceptedAt: latestDate(lhs.lastAcceptedAt, rhs.lastAcceptedAt),
                lastDismissedAt: latestDate(lhs.lastDismissedAt, rhs.lastDismissedAt),
                lastRefinedAt: latestDate(lhs.lastRefinedAt, rhs.lastRefinedAt)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedRepeatPattern(
        _ lhs: FoodMemoryRepeatPattern?,
        targetObservationCount: Int,
        _ rhs: FoodMemoryRepeatPattern?,
        sourceObservationCount: Int
    ) -> FoodMemoryRepeatPattern? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let totalObservationCount = targetObservationCount + sourceObservationCount
            let distinctConsumptionDays = min(
                lhs.distinctConsumptionDays + rhs.distinctConsumptionDays,
                max(totalObservationCount, 1)
            )
            let latestAnchor = max(lhs.currentDayAnchor, rhs.currentDayAnchor)
            let sameCurrentDay = Calendar.current.isDate(lhs.currentDayAnchor, inSameDayAs: rhs.currentDayAnchor)
            let currentDayUseCount: Int
            if sameCurrentDay {
                currentDayUseCount = lhs.currentDayUseCount + rhs.currentDayUseCount
            } else if lhs.currentDayAnchor > rhs.currentDayAnchor {
                currentDayUseCount = lhs.currentDayUseCount
            } else {
                currentDayUseCount = rhs.currentDayUseCount
            }

            let repeatGapObservationCount = lhs.repeatGapObservationCount + rhs.repeatGapObservationCount
            return FoodMemoryRepeatPattern(
                distinctConsumptionDays: distinctConsumptionDays,
                daysWithMultipleUses: min(lhs.daysWithMultipleUses + rhs.daysWithMultipleUses, distinctConsumptionDays),
                maxUsesInDay: max(max(lhs.maxUsesInDay, rhs.maxUsesInDay), currentDayUseCount),
                averageUsesPerDay: Double(totalObservationCount) / Double(max(distinctConsumptionDays, 1)),
                averageRepeatGapMinutes: weightedAverageOptional(lhs.averageRepeatGapMinutes, weight: lhs.repeatGapObservationCount, rhs.averageRepeatGapMinutes, weight: rhs.repeatGapObservationCount),
                repeatGapObservationCount: repeatGapObservationCount,
                currentDayUseCount: currentDayUseCount,
                currentDayAnchor: latestAnchor,
                lastConsumptionAt: max(lhs.lastConsumptionAt, rhs.lastConsumptionAt)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func mergedMatchStats(
        _ lhs: FoodMemoryMatchStats?,
        _ rhs: FoodMemoryMatchStats?
    ) -> FoodMemoryMatchStats? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return FoodMemoryMatchStats(
                acceptedMatches: lhs.acceptedMatches + rhs.acceptedMatches,
                rejectedMatches: lhs.rejectedMatches + rhs.rejectedMatches,
                ambiguousMatches: lhs.ambiguousMatches + rhs.ambiguousMatches,
                lastResolverVersion: max(lhs.lastResolverVersion, rhs.lastResolverVersion)
            )
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func rewireEntriesLinked(
        to sourceMemoryID: UUID,
        into targetMemoryID: UUID,
        entries: [FoodEntry]
    ) {
        let sourceIDString = sourceMemoryID.uuidString
        let targetIDString = targetMemoryID.uuidString

        for entry in entries where entry.foodMemoryIdString == sourceIDString {
            entry.foodMemoryIdString = targetIDString
        }
    }

    private func preferredDisplayName(
        from aliases: [FoodMemoryAlias],
        fallback: String,
        secondaryFallback: String
    ) -> String {
        aliases.first?.displayName ?? (fallback.isEmpty ? secondaryFallback : fallback)
    }

    private func preferredPrimaryNormalizedName(
        from aliases: [FoodMemoryAlias],
        fallback: String,
        secondaryFallback: String
    ) -> String {
        aliases.first?.normalizedName ?? (fallback.isEmpty ? secondaryFallback : fallback)
    }

    private func preferredEmoji(primary: String?, secondary: String?) -> String? {
        if let primary, !primary.isEmpty {
            return primary
        }
        if let secondary, !secondary.isEmpty {
            return secondary
        }
        return nil
    }

    private func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func preferredString(_ lhs: String?, _ rhs: String?, preferFirst: Bool) -> String? {
        if preferFirst {
            return lhs ?? rhs
        }
        return rhs ?? lhs
    }

    private func weightedAverage(
        _ lhs: Double,
        weight lhsWeight: Int,
        _ rhs: Double,
        weight rhsWeight: Int
    ) -> Double {
        let totalWeight = max(lhsWeight + rhsWeight, 1)
        return ((lhs * Double(lhsWeight)) + (rhs * Double(rhsWeight))) / Double(totalWeight)
    }

    private func weightedAverageOptional(
        _ lhs: Double?,
        weight lhsWeight: Int,
        _ rhs: Double?,
        weight rhsWeight: Int
    ) -> Double? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return weightedAverage(lhs, weight: lhsWeight, rhs, weight: rhsWeight)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func servingSignature(for snapshot: AcceptedFoodSnapshot) -> String {
        guard let quantity = snapshot.servingQuantity, let unit = snapshot.servingUnit else { return "" }
        return "\(Int((quantity * 10).rounded())):\(unit)"
    }

    private func blended(existing: Double, observed: Double, count: Int) -> Double {
        let priorWeight = Double(max(count, 1))
        return ((existing * priorWeight) + observed) / (priorWeight + 1)
    }

    private func blendedOptional(_ existing: Double?, _ observed: Double?, count: Int) -> Double? {
        switch (existing, observed) {
        case let (existing?, observed?):
            return blended(existing: existing, observed: observed, count: count)
        case let (existing?, nil):
            return existing
        case let (nil, observed?):
            return observed
        case (nil, nil):
            return nil
        }
    }
}
