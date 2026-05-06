import Foundation

struct FoodRecommendationReplayConfig: Sendable {
    let minimumTrainingObservations: Int
    let maximumCases: Int?
    let limits: [Int]
    let includeSessionContext: Bool

    init(
        minimumTrainingObservations: Int = 5,
        maximumCases: Int? = nil,
        limits: [Int] = [1, 3, 5],
        includeSessionContext: Bool = true
    ) {
        self.minimumTrainingObservations = minimumTrainingObservations
        self.maximumCases = maximumCases
        self.limits = limits
        self.includeSessionContext = includeSessionContext
    }
}

struct FoodRecommendationReplayMetrics: Sendable, Equatable {
    let evaluatedCases: Int
    let hitAt1: Double
    let hitAt3: Double
    let hitAt5: Double
    let meanReciprocalRank: Double
    let oneOffFalsePositiveRate: Double
    let beverageDominationRate: Double
    let completeMealCoverageRate: Double
    let duplicateSuggestionRate: Double
    let noSuggestionRate: Double
    let medianRuntimeMilliseconds: Double
    let p95RuntimeMilliseconds: Double
}

struct FoodRecommendationReplaySliceMetrics: Sendable, Equatable {
    let label: String
    let metrics: FoodRecommendationReplayMetrics
}

struct FoodRecommendationReplayFailedCase: Sendable, Equatable {
    let targetDate: Date
    let hiddenDisplayName: String
    let hiddenCanonicalComponents: [String]
    let topSuggestionTitles: [String]
    let topSuggestionCanonicalComponents: [[String]]
    let missReason: String
}

struct FoodRecommendationReplayDebugReport: Sendable, Equatable {
    let failedCases: [FoodRecommendationReplayFailedCase]
    let sliceMetrics: [FoodRecommendationReplaySliceMetrics]
}

struct FoodRecommendationReplayRunner {
    typealias RecommendationProvider = @MainActor (
        _ trainingEntries: [FoodEntry],
        _ memories: [FoodMemory],
        _ now: Date,
        _ limit: Int,
        _ sessionID: UUID?,
        _ currentSessionEntries: [FoodEntry]
    ) async throws -> [FoodSuggestion]

    private let normalizationService = FoodNormalizationService()

    @MainActor
    func evaluate(
        observations: [FoodObservation],
        entries: [FoodEntry],
        memories: [FoodMemory],
        provider: RecommendationProvider,
        config: FoodRecommendationReplayConfig
    ) async throws -> (metrics: FoodRecommendationReplayMetrics, debugReport: FoodRecommendationReplayDebugReport) {
        let sortedObservations = observations.sorted { $0.loggedAt < $1.loggedAt }
        let maxLimit = max(config.limits.max() ?? 5, 5)
        var cases: [ReplayCaseResult] = []

        let hiddenObservations = replayHiddenObservations(from: sortedObservations, config: config)
        for hiddenObservation in hiddenObservations {
            await Task.yield()
            let previousDayTrainingObservations = sortedObservations.filter {
                Calendar.current.startOfDay(for: $0.loggedAt) < Calendar.current.startOfDay(for: hiddenObservation.loggedAt)
            }
            let prefixObservations = sortedObservations.filter {
                $0.loggedAt < hiddenObservation.loggedAt
            }
            let currentSessionPrefix = config.includeSessionContext
                ? prefixObservations.filter {
                    $0.sessionID == hiddenObservation.sessionID && hiddenObservation.sessionID != nil
                }
                : []
            let trainingObservations = config.includeSessionContext
                ? prefixObservations
                : previousDayTrainingObservations

            let trainingEntryIDs = Set(trainingObservations.map(\.entryID))
            let trainingEntries = entries.filter { trainingEntryIDs.contains($0.id) }
            let currentSessionEntryIDs = Set(currentSessionPrefix.map(\.entryID))
            let currentSessionEntries = entries.filter { currentSessionEntryIDs.contains($0.id) }
            let start = Date()
            let suggestions = try await provider(
                trainingEntries,
                memories,
                hiddenObservation.loggedAt,
                maxLimit,
                config.includeSessionContext ? hiddenObservation.sessionID : nil,
                currentSessionEntries
            )
            let runtimeMilliseconds = Date().timeIntervalSince(start) * 1000
            cases.append(
                evaluateCase(
                    hidden: hiddenObservation,
                    training: trainingObservations,
                    suggestions: suggestions,
                    runtimeMilliseconds: runtimeMilliseconds,
                    hasSessionPrefix: !currentSessionEntries.isEmpty
                )
            )
            await Task.yield()
        }

        return (
            metrics: metrics(for: cases),
            debugReport: FoodRecommendationReplayDebugReport(
                failedCases: cases.compactMap(\.failedCase),
                sliceMetrics: sliceMetrics(for: cases)
            )
        )
    }

    private func replayHiddenObservations(
        from sortedObservations: [FoodObservation],
        config: FoodRecommendationReplayConfig
    ) -> [FoodObservation] {
        let eligible = sortedObservations.filter { hiddenObservation in
            let previousDayTrainingCount = sortedObservations.filter {
                Calendar.current.startOfDay(for: $0.loggedAt) < Calendar.current.startOfDay(for: hiddenObservation.loggedAt)
            }.count
            let prefixCount = sortedObservations.filter {
                $0.loggedAt < hiddenObservation.loggedAt
            }.count
            let trainingCount = config.includeSessionContext ? prefixCount : previousDayTrainingCount
            return trainingCount >= config.minimumTrainingObservations
        }

        guard let maximumCases = config.maximumCases, eligible.count > maximumCases else {
            return eligible
        }
        return Array(eligible.suffix(maximumCases))
    }

    private func evaluateCase(
        hidden: FoodObservation,
        training: [FoodObservation],
        suggestions: [FoodSuggestion],
        runtimeMilliseconds: Double,
        hasSessionPrefix: Bool
    ) -> ReplayCaseResult {
        let matchRanks = suggestions.enumerated().compactMap { index, suggestion in
            suggestionMatches(suggestion, hidden: hidden) ? index + 1 : nil
        }
        let firstRank = matchRanks.min()
        let topThree = Array(suggestions.prefix(3))
        let hiddenIsCompleteMeal = isCompleteMeal(hidden)
        let beverageDomination = hiddenIsCompleteMeal && !topThree.isEmpty && topThree.allSatisfy { isBeverage($0.suggestedEntry) }
        let completeMealCoverage = suggestions.prefix(5).contains { isCompleteMeal($0.suggestedEntry) }
        let duplicateSuggestion = hasDuplicateSuggestions(suggestions)
        let oneOffFalsePositive = firstRank == nil && suggestions.first.map { isOneOffSuggestion($0, training: training) } == true
        let failedCase = firstRank == nil ? FoodRecommendationReplayFailedCase(
            targetDate: hidden.loggedAt,
            hiddenDisplayName: hidden.displayName,
            hiddenCanonicalComponents: hidden.components.map(\.canonicalName).sorted(),
            topSuggestionTitles: suggestions.prefix(5).map(\.title),
            topSuggestionCanonicalComponents: suggestions.prefix(5).map(canonicalComponents(for:)),
            missReason: beverageDomination ? "beverageDomination" : "noCloseEquivalent"
        ) : nil

        return ReplayCaseResult(
            reciprocalRank: firstRank.map { 1 / Double($0) } ?? 0,
            hitAt1: firstRank.map { $0 <= 1 } ?? false,
            hitAt3: firstRank.map { $0 <= 3 } ?? false,
            hitAt5: firstRank.map { $0 <= 5 } ?? false,
            oneOffFalsePositive: oneOffFalsePositive,
            beverageDomination: beverageDomination,
            completeMealCoverage: completeMealCoverage,
            duplicateSuggestion: duplicateSuggestion,
            noSuggestion: suggestions.isEmpty,
            runtimeMilliseconds: runtimeMilliseconds,
            targetDate: hidden.loggedAt,
            hasSessionPrefix: hasSessionPrefix,
            failedCase: failedCase
        )
    }

    private func sliceMetrics(for cases: [ReplayCaseResult]) -> [FoodRecommendationReplaySliceMetrics] {
        let timeSlices: [(String, (Int) -> Bool)] = [
            ("5am-10am", { 5..<10 ~= $0 }),
            ("10am-2pm", { 10..<14 ~= $0 }),
            ("2pm-5pm", { 14..<17 ~= $0 }),
            ("5pm-9pm", { 17..<21 ~= $0 }),
            ("9pm-1am", { $0 >= 21 || $0 < 1 })
        ]
        let calendar = Calendar.current
        var slices = timeSlices.map { label, containsHour in
            let matching = cases.filter { containsHour(calendar.component(.hour, from: $0.targetDate)) }
            return FoodRecommendationReplaySliceMetrics(label: label, metrics: metrics(for: matching))
        }
        let weekdayCases = cases.filter { !calendar.isDateInWeekend($0.targetDate) }
        let weekendCases = cases.filter { calendar.isDateInWeekend($0.targetDate) }
        let withSessionPrefix = cases.filter(\.hasSessionPrefix)
        let withoutSessionPrefix = cases.filter { !$0.hasSessionPrefix }
        slices.append(FoodRecommendationReplaySliceMetrics(label: "weekday", metrics: metrics(for: weekdayCases)))
        slices.append(FoodRecommendationReplaySliceMetrics(label: "weekend", metrics: metrics(for: weekendCases)))
        slices.append(FoodRecommendationReplaySliceMetrics(label: "with session prefix", metrics: metrics(for: withSessionPrefix)))
        slices.append(FoodRecommendationReplaySliceMetrics(label: "without session prefix", metrics: metrics(for: withoutSessionPrefix)))
        return slices
    }

    private func metrics(for cases: [ReplayCaseResult]) -> FoodRecommendationReplayMetrics {
        guard !cases.isEmpty else {
            return FoodRecommendationReplayMetrics(
                evaluatedCases: 0,
                hitAt1: 0,
                hitAt3: 0,
                hitAt5: 0,
                meanReciprocalRank: 0,
                oneOffFalsePositiveRate: 0,
                beverageDominationRate: 0,
                completeMealCoverageRate: 0,
                duplicateSuggestionRate: 0,
                noSuggestionRate: 0,
                medianRuntimeMilliseconds: 0,
                p95RuntimeMilliseconds: 0
            )
        }

        let count = Double(cases.count)
        let runtimes = cases.map(\.runtimeMilliseconds).sorted()
        return FoodRecommendationReplayMetrics(
            evaluatedCases: cases.count,
            hitAt1: rate(cases, \.hitAt1, count: count),
            hitAt3: rate(cases, \.hitAt3, count: count),
            hitAt5: rate(cases, \.hitAt5, count: count),
            meanReciprocalRank: cases.map(\.reciprocalRank).reduce(0, +) / count,
            oneOffFalsePositiveRate: rate(cases, \.oneOffFalsePositive, count: count),
            beverageDominationRate: rate(cases, \.beverageDomination, count: count),
            completeMealCoverageRate: rate(cases, \.completeMealCoverage, count: count),
            duplicateSuggestionRate: rate(cases, \.duplicateSuggestion, count: count),
            noSuggestionRate: rate(cases, \.noSuggestion, count: count),
            medianRuntimeMilliseconds: percentile(runtimes, percentile: 0.50),
            p95RuntimeMilliseconds: percentile(runtimes, percentile: 0.95)
        )
    }

    private func rate(_ cases: [ReplayCaseResult], _ keyPath: KeyPath<ReplayCaseResult, Bool>, count: Double) -> Double {
        Double(cases.filter { $0[keyPath: keyPath] }.count) / count
    }

    private func percentile(_ sortedValues: [Double], percentile: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * clamped).rounded(.up))
        return sortedValues[min(max(index, 0), sortedValues.count - 1)]
    }

    private func suggestionMatches(_ suggestion: FoodSuggestion, hidden: FoodObservation) -> Bool {
        if suggestion.memoryID == hidden.linkedMemoryID {
            return true
        }
        if normalizationService.normalizeFoodName(suggestion.title) == hidden.normalizedName {
            return true
        }

        let suggestionComponents = Set(canonicalComponents(for: suggestion))
        let hiddenComponents = Set(hidden.components.map(\.canonicalName))
        if !suggestionComponents.isEmpty, !hiddenComponents.isEmpty {
            let intersection = suggestionComponents.intersection(hiddenComponents).count
            let union = suggestionComponents.union(hiddenComponents).count
            let jaccard = Double(intersection) / Double(max(union, 1))
            if jaccard >= 0.67 && macroCompatible(suggestion.suggestedEntry, hidden: hidden) {
                return true
            }
        }

        let suggestionTokens = Set(normalizationService.normalizeFoodName(suggestion.title).split(separator: " "))
        let hiddenTokens = Set(hidden.normalizedName.split(separator: " "))
        let tokenOverlap = Double(suggestionTokens.intersection(hiddenTokens).count) / Double(max(suggestionTokens.union(hiddenTokens).count, 1))
        return tokenOverlap >= 0.75 && macroCompatible(suggestion.suggestedEntry, hidden: hidden)
    }

    private func canonicalComponents(for suggestion: FoodSuggestion) -> [String] {
        canonicalComponents(for: suggestion.suggestedEntry)
    }

    private func canonicalComponents(for entry: SuggestedFoodEntry) -> [String] {
        let components = entry.components.map { normalizationService.normalizeComponentName($0.displayName) }
        if !components.isEmpty {
            return Array(Set(components)).sorted()
        }
        return normalizationService.normalizeFoodName(entry.name).split(separator: " ").map(String.init).sorted()
    }

    private func macroCompatible(_ suggestion: SuggestedFoodEntry, hidden: FoodObservation) -> Bool {
        let calorieDistance = abs(Double(suggestion.calories - hidden.calories)) / Double(max(hidden.calories, 1))
        let proteinDistance = abs(suggestion.proteinGrams - hidden.proteinGrams) / max(hidden.proteinGrams, 1)
        return calorieDistance <= 0.35 && proteinDistance <= 0.45
    }

    private func isOneOffSuggestion(_ suggestion: FoodSuggestion, training: [FoodObservation]) -> Bool {
        let suggestionComponents = Set(canonicalComponents(for: suggestion))
        let matching = training.filter { observation in
            Set(observation.components.map(\.canonicalName)) == suggestionComponents
        }
        let distinctDays = Set(matching.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count
        return distinctDays < 2
    }

    private func hasDuplicateSuggestions(_ suggestions: [FoodSuggestion]) -> Bool {
        var seen = Set<[String]>()
        for signature in suggestions.map(canonicalComponents(for:)) {
            guard seen.insert(signature).inserted else { return true }
        }
        return false
    }

    private func isBeverage(_ entry: SuggestedFoodEntry) -> Bool {
        let title = entry.name.lowercased()
        return entry.components.contains { $0.role == FoodComponentRole.drink.rawValue }
            || title.contains("latte")
            || title.contains("coffee")
            || title.contains("cappuccino")
    }

    private func isCompleteMeal(_ observation: FoodObservation) -> Bool {
        let roles = Set(observation.components.map(\.role))
        return (roles.contains(.protein) && (roles.contains(.carb) || roles.contains(.vegetable) || roles.contains(.fruit) || roles.contains(.mixed)))
            || (observation.calories >= 450 && observation.components.count >= 2)
    }

    private func isCompleteMeal(_ entry: SuggestedFoodEntry) -> Bool {
        let roles = Set(entry.components.compactMap { $0.role.flatMap(FoodComponentRole.init(rawValue:)) })
        return (roles.contains(.protein) && (roles.contains(.carb) || roles.contains(.vegetable) || roles.contains(.fruit) || roles.contains(.mixed)))
            || (entry.calories >= 450 && entry.components.count >= 2)
    }
}

struct FoodRecommendationEvaluator {
    @MainActor
    func evaluate(
        entries: [FoodEntry],
        memories: [FoodMemory],
        config: FoodRecommendationReplayConfig
    ) async throws -> FoodRecommendationReplayMetrics {
        let observations = FoodObservationBuilder().observations(from: entries)
        let runner = FoodRecommendationReplayRunner()
        let result = try await runner.evaluate(
            observations: observations,
            entries: entries,
            memories: memories,
            provider: { trainingEntries, memories, now, limit, sessionID, _ in
                FoodRecommendationEngine().recommendationsSync(
                    for: FoodRecommendationRequest(
                        now: now,
                        targetDate: now,
                        sessionID: sessionID,
                        limit: limit,
                        entries: trainingEntries,
                        memories: memories
                    )
                ).suggestions
            },
            config: config
        )
        return result.metrics
    }
}

private struct ReplayCaseResult {
    let reciprocalRank: Double
    let hitAt1: Bool
    let hitAt3: Bool
    let hitAt5: Bool
    let oneOffFalsePositive: Bool
    let beverageDomination: Bool
    let completeMealCoverage: Bool
    let duplicateSuggestion: Bool
    let noSuggestion: Bool
    let runtimeMilliseconds: Double
    let targetDate: Date
    let hasSessionPrefix: Bool
    let failedCase: FoodRecommendationReplayFailedCase?
}
