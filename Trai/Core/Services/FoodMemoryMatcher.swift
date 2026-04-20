import Foundation

struct FoodMemoryMatchExplanation: Codable, Sendable {
    let resolverVersion: Int
    let topSignals: [String]
    let penalties: [String]
    let consideredMemoryIds: [UUID]
    let winningScore: Double
    let runnerUpScore: Double?
}

enum FoodMemoryMatchOutcome: String, Codable, Sendable {
    case matched
    case createCandidate
    case reject
}

struct FoodMemoryMatchResult: Sendable {
    let outcome: FoodMemoryMatchOutcome
    let memoryId: UUID?
    let confidence: Double
    let explanation: FoodMemoryMatchExplanation
}

struct FoodMemoryMatcher {
    let resolverVersion: Int
    private let normalizationService = FoodNormalizationService()
    private let snapshotBuilder = FoodSnapshotBuilder()

    init(resolverVersion: Int = 1) {
        self.resolverVersion = resolverVersion
    }

    func representsSameHabit(_ lhs: FoodMemory, _ rhs: FoodMemory) -> Bool {
        if lhs.id == rhs.id || lhs.kind != rhs.kind {
            return lhs.id == rhs.id
        }

        if lhs.primaryNormalizedName == rhs.primaryNormalizedName,
           !lhs.primaryNormalizedName.isEmpty {
            return true
        }

        let lhsAliases = Set(lhs.aliases.map(\.normalizedName)).union([lhs.primaryNormalizedName])
        let rhsAliases = Set(rhs.aliases.map(\.normalizedName)).union([rhs.primaryNormalizedName])
        if !lhsAliases.intersection(rhsAliases).isEmpty {
            return true
        }

        guard let lhsSnapshot = synthesizedSnapshot(from: lhs) else { return false }
        let rhsResult = match(snapshot: lhsSnapshot, candidates: [rhs])
        if rhsResult.outcome == .matched {
            return true
        }

        guard let rhsSnapshot = synthesizedSnapshot(from: rhs) else { return false }
        let lhsResult = match(snapshot: rhsSnapshot, candidates: [lhs])
        return lhsResult.outcome == .matched
    }

    func matches(memory: FoodMemory, snapshot: AcceptedFoodSnapshot) -> Bool {
        let normalizedEntryName = snapshot.normalizedDisplayName
        let memoryAliases = Set(memory.aliases.map(\.normalizedName)).union([memory.primaryNormalizedName])
        if !normalizedEntryName.isEmpty,
           memoryAliases.contains(normalizedEntryName),
           nutritionLooksCompatible(snapshot: snapshot, memory: memory) {
            return true
        }

        let result = match(snapshot: snapshot, candidates: [memory])
        return result.outcome == .matched
    }

    func matches(entry: FoodEntry, memory: FoodMemory) -> Bool {
        let normalizedEntryName = normalizationService.normalizeFoodName(entry.name)
        let memoryAliases = Set(memory.aliases.map(\.normalizedName)).union([memory.primaryNormalizedName])
        if !normalizedEntryName.isEmpty,
           memoryAliases.contains(normalizedEntryName),
           nutritionLooksCompatible(entry: entry, memory: memory) {
            return true
        }

        guard let snapshot = snapshot(for: entry) else { return false }
        return matches(memory: memory, snapshot: snapshot)
    }

    func match(
        snapshot: AcceptedFoodSnapshot,
        candidates: [FoodMemory]
    ) -> FoodMemoryMatchResult {
        guard !candidates.isEmpty else {
            return FoodMemoryMatchResult(
                outcome: .createCandidate,
                memoryId: nil,
                confidence: 0,
                explanation: FoodMemoryMatchExplanation(
                    resolverVersion: resolverVersion,
                    topSignals: ["No candidate memories available"],
                    penalties: [],
                    consideredMemoryIds: [],
                    winningScore: 0,
                    runnerUpScore: nil
                )
            )
        }

        let scored = candidates.compactMap { memory -> ScoredCandidate? in
            score(memory: memory, against: snapshot)
        }

        guard let best = scored.max(by: { $0.score < $1.score }) else {
            return FoodMemoryMatchResult(
                outcome: .createCandidate,
                memoryId: nil,
                confidence: 0,
                explanation: FoodMemoryMatchExplanation(
                    resolverVersion: resolverVersion,
                    topSignals: ["No structurally valid candidates"],
                    penalties: ["Hard-fail mismatch on kind or dominant components"],
                    consideredMemoryIds: candidates.map(\.id),
                    winningScore: 0,
                    runnerUpScore: nil
                )
            )
        }

        let runnerUp = scored
            .filter { $0.memory.id != best.memory.id }
            .max(by: { $0.score < $1.score })

        let scoreGap = best.score - (runnerUp?.score ?? 0)
        let shouldMatch = best.score >= 0.82 && scoreGap >= 0.06

        return FoodMemoryMatchResult(
            outcome: shouldMatch ? .matched : .createCandidate,
            memoryId: shouldMatch ? best.memory.id : nil,
            confidence: best.score,
            explanation: FoodMemoryMatchExplanation(
                resolverVersion: resolverVersion,
                topSignals: best.signals,
                penalties: best.penalties,
                consideredMemoryIds: scored.map { $0.memory.id },
                winningScore: best.score,
                runnerUpScore: runnerUp?.score
            )
        )
    }

    private func score(memory: FoodMemory, against snapshot: AcceptedFoodSnapshot) -> ScoredCandidate? {
        let memoryComponentNames = Set(memory.components.map(\.normalizedName))
        let snapshotComponentNames = Set(snapshot.components.map(\.normalizedName))

        if hardFails(memory: memory, snapshot: snapshot, memoryComponentNames: memoryComponentNames, snapshotComponentNames: snapshotComponentNames) {
            return nil
        }

        let componentScore = componentSimilarity(memoryNames: memoryComponentNames, snapshotNames: snapshotComponentNames)
        let roleScore = jaccard(
            lhs: Set(memory.components.map(\.role.rawValue)),
            rhs: Set(snapshot.components.map(\.role.rawValue))
        )
        let nameScore = bestNameSimilarity(memory: memory, snapshot: snapshot)
        let macroScore = macroProximity(memory: memory, snapshot: snapshot)
        let servingScore = servingSimilarity(memory: memory, snapshot: snapshot)
        let dominantProteinScore = dominantAlignmentScore(
            memoryComponents: memory.components,
            snapshotComponents: snapshot.components,
            preferredRoles: [.protein, .mixed]
        )
        let dominantCarbScore = dominantAlignmentScore(
            memoryComponents: memory.components,
            snapshotComponents: snapshot.components,
            preferredRoles: [.carb, .mixed]
        )
        let mealTimeScore: Double = memory.fingerprints.contains {
            $0.type == .mealTimeBucket && $0.value == snapshot.mealTimeBucket.rawValue
        } ? 1.0 : 0.0
        let qualityScore = qualityScore(for: memory)

        let weightedComponents =
            (componentScore * 0.24) +
            (macroScore * 0.18) +
            (nameScore * 0.16) +
            (servingScore * 0.10) +
            (roleScore * 0.10) +
            (dominantProteinScore * 0.08) +
            (dominantCarbScore * 0.06) +
            (mealTimeScore * 0.04) +
            (qualityScore * 0.04)
        let weightedScore = min(max(weightedComponents, 0), 1)

        var topSignals: [String] = []
        if componentScore > 0 { topSignals.append("Component overlap \(format(componentScore))") }
        if macroScore > 0 { topSignals.append("Macro proximity \(format(macroScore))") }
        if nameScore > 0 { topSignals.append("Name similarity \(format(nameScore))") }
        if servingScore > 0 { topSignals.append("Serving similarity \(format(servingScore))") }
        if dominantProteinScore > 0.9 { topSignals.append("Dominant protein aligned") }
        if dominantCarbScore > 0.9 { topSignals.append("Dominant carb/base aligned") }
        if mealTimeScore > 0 { topSignals.append("Consistent meal-time bucket") }

        var penalties: [String] = []
        if componentScore == 0 && !memoryComponentNames.isEmpty && !snapshotComponentNames.isEmpty {
            penalties.append("No shared normalized components")
        }
        if macroScore < 0.45 {
            penalties.append("Macro profile differs materially")
        }
        if nameScore == 0 {
            penalties.append("Observed names share no normalized tokens")
        }
        if dominantProteinScore == 0 {
            penalties.append("Dominant protein does not align")
        }

        return ScoredCandidate(
            memory: memory,
            score: weightedScore,
            signals: topSignals,
            penalties: penalties
        )
    }

    private func hardFails(
        memory: FoodMemory,
        snapshot: AcceptedFoodSnapshot,
        memoryComponentNames: Set<String>,
        snapshotComponentNames: Set<String>
    ) -> Bool {
        if memory.kind != snapshot.kind && min(memoryComponentNames.count, snapshotComponentNames.count) <= 1 {
            return true
        }

        let dominantMemoryProtein = dominantComponent(
            roles: [.protein, .mixed],
            from: memory.components
        )?.normalizedName
        let dominantSnapshotProtein = dominantComponent(
            roles: [.protein, .mixed],
            from: snapshot.components
        )?.normalizedName

        if let dominantMemoryProtein, let dominantSnapshotProtein,
           dominantMemoryProtein != dominantSnapshotProtein,
           macroProximity(memory: memory, snapshot: snapshot) < 0.55,
           componentSimilarity(memoryNames: memoryComponentNames, snapshotNames: snapshotComponentNames) < 0.45 {
            return true
        }

        return false
    }

    private func dominantComponent(
        roles: Set<FoodComponentRole>,
        from components: [FoodMemoryComponentSummary]
    ) -> FoodMemoryComponentSummary? {
        components
            .filter { roles.contains($0.role) }
            .max { lhs, rhs in lhs.observationCount < rhs.observationCount }
    }

    private func dominantComponent(
        roles: Set<FoodComponentRole>,
        from components: [AcceptedFoodComponent]
    ) -> AcceptedFoodComponent? {
        components
            .filter { roles.contains($0.role) }
            .max { lhs, rhs in lhs.calories < rhs.calories }
    }

    private func macroProximity(memory: FoodMemory, snapshot: AcceptedFoodSnapshot) -> Double {
        guard let nutrition = memory.nutritionProfile else { return 0 }

        let calorieScore = normalizedDistanceScore(
            expected: Double(nutrition.medianCalories),
            observed: Double(snapshot.totalCalories),
            tolerance: max(Double(nutrition.medianCalories) * 0.35, 120)
        )
        let proteinScore = normalizedDistanceScore(
            expected: nutrition.medianProteinGrams,
            observed: snapshot.totalProteinGrams,
            tolerance: max(nutrition.medianProteinGrams * 0.45, 12)
        )
        let carbsScore = normalizedDistanceScore(
            expected: nutrition.medianCarbsGrams,
            observed: snapshot.totalCarbsGrams,
            tolerance: max(nutrition.medianCarbsGrams * 0.45, 16)
        )
        let fatScore = normalizedDistanceScore(
            expected: nutrition.medianFatGrams,
            observed: snapshot.totalFatGrams,
            tolerance: max(nutrition.medianFatGrams * 0.45, 8)
        )

        return (calorieScore + proteinScore + carbsScore + fatScore) / 4
    }

    private func servingSimilarity(memory: FoodMemory, snapshot: AcceptedFoodSnapshot) -> Double {
        guard let servingProfile = memory.servingProfile else { return 0 }
        let unitScore: Double
        if let memoryUnit = servingProfile.commonUnit, let snapshotUnit = snapshot.servingUnit {
            unitScore = memoryUnit == snapshotUnit ? 1 : 0
        } else {
            unitScore = 0
        }

        let quantityScore: Double
        if let memoryQuantity = servingProfile.commonQuantity, let snapshotQuantity = snapshot.servingQuantity {
            let tolerance = max(servingProfile.quantityVariance ?? 0.25, 0.25)
            quantityScore = normalizedDistanceScore(
                expected: memoryQuantity,
                observed: snapshotQuantity,
                tolerance: tolerance
            )
        } else {
            quantityScore = 0
        }

        if unitScore > 0 || quantityScore > 0 {
            return max((unitScore * 0.55) + (quantityScore * 0.45), max(unitScore, quantityScore))
        }

        guard let memoryServing = servingProfile.commonServingText?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              let snapshotServing = snapshot.servingText?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !memoryServing.isEmpty,
              !snapshotServing.isEmpty else {
            return 0
        }

        return memoryServing == snapshotServing ? 1 : 0
    }

    private func normalizedDistanceScore(expected: Double, observed: Double, tolerance: Double) -> Double {
        guard tolerance > 0 else { return expected == observed ? 1 : 0 }
        return max(0, 1 - (abs(expected - observed) / tolerance))
    }

    private func jaccard<T: Hashable>(lhs: Set<T>, rhs: Set<T>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private func componentSimilarity(
        memoryNames: Set<String>,
        snapshotNames: Set<String>
    ) -> Double {
        let jaccardScore = jaccard(lhs: memoryNames, rhs: snapshotNames)
        let forwardCoverage = overlapCoverage(observed: snapshotNames, reference: memoryNames)
        let reverseCoverage = overlapCoverage(observed: memoryNames, reference: snapshotNames)
        return max(jaccardScore, (forwardCoverage * 0.65) + (reverseCoverage * 0.35))
    }

    private func bestNameSimilarity(memory: FoodMemory, snapshot: AcceptedFoodSnapshot) -> Double {
        let snapshotTokenSets = snapshot.nameAliases.map(tokenSet(from:))
        let memoryNameVariants = Set(
            [memory.primaryNormalizedName]
                + memory.aliases.map(\.normalizedName)
                + memory.fingerprints
                    .filter { $0.type == .normalizedName }
                    .map(\.value)
        )

        var bestScore = 0.0
        for variant in memoryNameVariants {
            let memoryTokens = tokenSet(from: variant)
            for snapshotTokens in snapshotTokenSets {
                bestScore = max(bestScore, tokenOverlapScore(lhs: memoryTokens, rhs: snapshotTokens))
            }
        }
        return bestScore
    }

    private func dominantAlignmentScore(
        memoryComponents: [FoodMemoryComponentSummary],
        snapshotComponents: [AcceptedFoodComponent],
        preferredRoles: Set<FoodComponentRole>
    ) -> Double {
        let memoryDominant = dominantComponent(roles: preferredRoles, from: memoryComponents)?.normalizedName
        let snapshotDominant = dominantComponent(roles: preferredRoles, from: snapshotComponents)?.normalizedName

        switch (memoryDominant, snapshotDominant) {
        case let (lhs?, rhs?):
            return lhs == rhs ? 1 : 0
        case (nil, nil):
            return 0.5
        default:
            return 0.35
        }
    }

    private func qualityScore(for memory: FoodMemory) -> Double {
        guard let signals = memory.qualitySignals else { return 0 }
        return min(
            max(
                (signals.proportionWithStructuredComponents * 0.6) +
                (min(Double(signals.distinctObservationDays), 5) / 5 * 0.2) +
                (signals.repeatedTimeBucketScore * 0.2),
                0
            ),
            1
        )
    }

    private func overlapCoverage(observed: Set<String>, reference: Set<String>) -> Double {
        guard !observed.isEmpty, !reference.isEmpty else { return 0 }
        return Double(observed.intersection(reference).count) / Double(observed.count)
    }

    private func tokenSet(from value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private func tokenOverlapScore(lhs: Set<String>, rhs: Set<String>) -> Double {
        max(jaccard(lhs: lhs, rhs: rhs), overlapCoverage(observed: rhs, reference: lhs))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func nutritionLooksCompatible(entry: FoodEntry, memory: FoodMemory) -> Bool {
        guard let nutrition = memory.nutritionProfile else { return true }

        let calorieTolerance = max(Double(nutrition.medianCalories) * 0.4, 120)
        let proteinTolerance = max(nutrition.medianProteinGrams * 0.5, 12)
        let carbsTolerance = max(nutrition.medianCarbsGrams * 0.5, 18)
        let fatTolerance = max(nutrition.medianFatGrams * 0.5, 10)

        return
            abs(Double(entry.calories - nutrition.medianCalories)) <= calorieTolerance &&
            abs(entry.proteinGrams - nutrition.medianProteinGrams) <= proteinTolerance &&
            abs(entry.carbsGrams - nutrition.medianCarbsGrams) <= carbsTolerance &&
            abs(entry.fatGrams - nutrition.medianFatGrams) <= fatTolerance
    }

    private func nutritionLooksCompatible(snapshot: AcceptedFoodSnapshot, memory: FoodMemory) -> Bool {
        guard let nutrition = memory.nutritionProfile else { return true }

        let calorieTolerance = max(Double(nutrition.medianCalories) * 0.4, 120)
        let proteinTolerance = max(nutrition.medianProteinGrams * 0.5, 12)
        let carbsTolerance = max(nutrition.medianCarbsGrams * 0.5, 18)
        let fatTolerance = max(nutrition.medianFatGrams * 0.5, 10)

        return
            abs(Double(snapshot.totalCalories - nutrition.medianCalories)) <= calorieTolerance &&
            abs(snapshot.totalProteinGrams - nutrition.medianProteinGrams) <= proteinTolerance &&
            abs(snapshot.totalCarbsGrams - nutrition.medianCarbsGrams) <= carbsTolerance &&
            abs(snapshot.totalFatGrams - nutrition.medianFatGrams) <= fatTolerance
    }

    private func snapshot(for entry: FoodEntry) -> AcceptedFoodSnapshot? {
        if let acceptedSnapshot = entry.acceptedSnapshot {
            return acceptedSnapshot
        }

        if !entry.acceptedComponents.isEmpty {
            let normalizedName = normalizationService.normalizeFoodName(entry.name)
            return AcceptedFoodSnapshot(
                version: resolverVersion,
                source: acceptedSource(for: entry),
                kind: entry.acceptedComponents.count > 1 ? .meal : .food,
                displayName: entry.name,
                emoji: entry.emoji,
                normalizedDisplayName: normalizedName,
                nameAliases: normalizationService.aliasCandidates(for: entry.name),
                mealLabel: entry.mealType,
                servingText: entry.servingSize,
                servingQuantity: entry.servingQuantity > 0 ? entry.servingQuantity : nil,
                servingUnit: nil,
                totalCalories: entry.calories,
                totalProteinGrams: entry.proteinGrams,
                totalCarbsGrams: entry.carbsGrams,
                totalFatGrams: entry.fatGrams,
                totalFiberGrams: entry.fiberGrams,
                totalSugarGrams: entry.sugarGrams,
                components: entry.acceptedComponents,
                notes: entry.aiAnalysis,
                confidence: nil,
                loggedAt: entry.loggedAt,
                mealTimeBucket: normalizationService.mealTimeBucket(for: entry.loggedAt),
                weekdayBucket: Calendar.current.component(.weekday, from: entry.loggedAt),
                userEditedFields: [],
                wasUserEdited: entry.foodMemoryWasUserEdited
            )
        }

        return snapshotBuilder.buildAcceptedSnapshot(
            from: entry,
            source: acceptedSource(for: entry)
        )
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

    private func synthesizedSnapshot(from memory: FoodMemory) -> AcceptedFoodSnapshot? {
        guard let nutrition = memory.nutritionProfile else { return nil }

        let servingQuantity = memory.servingProfile?.commonQuantity
        let servingUnit = memory.servingProfile?.commonUnit
        let servingText = memory.servingProfile?.commonServingText
        let normalizedDisplayName = memory.primaryNormalizedName.isEmpty
            ? normalizationService.normalizeFoodName(memory.displayName)
            : memory.primaryNormalizedName
        let aliases = Array(
            Set(memory.aliases.map(\.normalizedName) + [normalizedDisplayName]).filter { !$0.isEmpty }
        )

        return AcceptedFoodSnapshot(
            version: resolverVersion,
            source: .memorySuggestion,
            kind: memory.kind,
            displayName: memory.displayName,
            emoji: memory.emoji,
            normalizedDisplayName: normalizedDisplayName,
            nameAliases: aliases,
            mealLabel: nil,
            servingText: servingText,
            servingQuantity: servingQuantity,
            servingUnit: servingUnit,
            totalCalories: nutrition.medianCalories,
            totalProteinGrams: nutrition.medianProteinGrams,
            totalCarbsGrams: nutrition.medianCarbsGrams,
            totalFatGrams: nutrition.medianFatGrams,
            totalFiberGrams: nutrition.medianFiberGrams,
            totalSugarGrams: nutrition.medianSugarGrams,
            components: memory.components.map { component in
                AcceptedFoodComponent(
                    id: component.normalizedName,
                    displayName: displayName(forNormalizedComponent: component.normalizedName),
                    normalizedName: component.normalizedName,
                    role: component.role,
                    quantity: nil,
                    unit: nil,
                    calories: component.typicalCalories,
                    proteinGrams: component.typicalProteinGrams,
                    carbsGrams: component.typicalCarbsGrams,
                    fatGrams: component.typicalFatGrams,
                    fiberGrams: nil,
                    sugarGrams: nil,
                    preparation: nil,
                    confidence: memory.status == .confirmed ? .high : .medium,
                    source: .derived
                )
            },
            notes: nil,
            confidence: memory.status == .confirmed ? .high : .medium,
            loggedAt: memory.lastObservedAt,
            mealTimeBucket: memoryMealTimeBucket(for: memory) ?? normalizationService.mealTimeBucket(for: memory.lastObservedAt),
            weekdayBucket: Calendar.current.component(.weekday, from: memory.lastObservedAt),
            userEditedFields: [],
            wasUserEdited: false
        )
    }

    private func memoryMealTimeBucket(for memory: FoodMemory) -> MealTimeBucket? {
        if let dominantBucket = memory.timeProfile.flatMap({ dominantBucket(in: $0) }) {
            return dominantBucket
        }
        return memory.fingerprints
            .first(where: { $0.type == .mealTimeBucket })
            .flatMap { MealTimeBucket(rawValue: $0.value) }
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

    private func displayName(forNormalizedComponent normalizedName: String) -> String {
        normalizedName
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct ScoredCandidate {
    let memory: FoodMemory
    let score: Double
    let signals: [String]
    let penalties: [String]
}
