import Foundation

struct FoodPatternRankerDiagnostics: Sendable, Equatable {
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowConfidenceCount: Int
}

struct FoodPatternRanker {
    func rank(_ candidates: [FoodPatternSuggestion], context: FoodPatternRecommendationContext) -> [FoodPatternSuggestion] {
        let filtered = candidates.filter { !suppressionReasons(for: $0, context: context).isSuppressed }
        let bestByPattern = Dictionary(grouping: filtered, by: \.pattern.id).compactMap { _, candidates in
            candidates.max {
                $0.score < $1.score
            }
        }
        let sorted = bestByPattern.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.pattern.lastObservedAt > $1.pattern.lastObservedAt
        }
        return applyDiversityPolicy(to: sorted, limit: context.limit)
    }

    func diagnostics(
        for candidates: [FoodPatternSuggestion],
        context: FoodPatternRecommendationContext
    ) -> FoodPatternRankerDiagnostics {
        var oneOff = Set<String>()
        var alreadyToday = Set<String>()
        var negative = Set<String>()
        var lowConfidence = Set<String>()

        for candidate in candidates {
            let reasons = suppressionReasons(for: candidate, context: context)
            if reasons.oneOff { oneOff.insert(candidate.pattern.id) }
            if reasons.alreadyToday { alreadyToday.insert(candidate.pattern.id) }
            if reasons.negativeFeedback { negative.insert(candidate.pattern.id) }
            if reasons.lowConfidence { lowConfidence.insert(candidate.pattern.id) }
        }

        return FoodPatternRankerDiagnostics(
            suppressedOneOffCount: oneOff.count,
            suppressedAlreadyTodayCount: alreadyToday.count,
            suppressedNegativeFeedbackCount: negative.count,
            suppressedLowConfidenceCount: lowConfidence.count
        )
    }

    func features(
        for pattern: FoodPattern,
        sourceBoost: Double,
        context: FoodPatternRecommendationContext
    ) -> FoodPatternRankingFeatures {
        FoodPatternRankingFeatures(
            repetition: min(Double(pattern.distinctDays) / 6.0, 1),
            recency: Self.recencyScore(for: pattern, targetDate: context.targetDate),
            timeSupport: Self.timeSupport(for: pattern, targetDate: context.targetDate),
            dayTypeSupport: Self.dayTypeSupport(for: pattern, targetDate: context.targetDate),
            sessionSupport: Self.sessionSupport(for: pattern, context: context),
            patternConfidence: patternConfidence(for: pattern),
            practicalUtility: practicalUtility(for: pattern),
            positiveFeedback: min(Double(pattern.feedbackProfile.timesAccepted + pattern.feedbackProfile.timesRefined) / 3.0, 1),
            negativeFeedbackPenalty: negativeFeedbackPenalty(for: pattern, now: context.now),
            sourceBoost: sourceBoost
        )
    }

    func score(_ features: FoodPatternRankingFeatures) -> Double {
        let rawScore =
            0.16 * features.repetition +
            0.10 * features.recency +
            0.19 * features.timeSupport +
            0.06 * features.dayTypeSupport +
            0.15 * features.sessionSupport +
            0.12 * features.patternConfidence +
            0.16 * features.practicalUtility +
            0.08 * features.positiveFeedback +
            features.sourceBoost -
            features.negativeFeedbackPenalty
        return min(max(rawScore, 0), 1)
    }

    private func suppressionReasons(
        for suggestion: FoodPatternSuggestion,
        context: FoodPatternRecommendationContext
    ) -> FoodPatternSuppressionReasons {
        let pattern = suggestion.pattern
        let oneOff = suggestion.source != .continueSession
            && pattern.distinctDays < 2
            && pattern.feedbackProfile.timesAccepted == 0
            && pattern.feedbackProfile.timesRefined == 0
        let alreadyToday = isAlreadyLoggedToday(pattern, context: context) && !supportsSameDayRepeat(pattern, context: context)
        let negativeFeedback = suggestion.features.negativeFeedbackPenalty >= 1.0
        let lowConfidence = suggestion.features.patternConfidence < 0.42
            && suggestion.features.sessionSupport < 0.55
            && suggestion.features.positiveFeedback == 0
        let weakSimpleRepeat = isLowSubstantiality(pattern)
            && suggestion.features.timeSupport < 0.18
            && suggestion.features.sessionSupport == 0
            && pattern.distinctDays < 4
            && suggestion.features.positiveFeedback == 0

        return FoodPatternSuppressionReasons(
            oneOff: oneOff,
            alreadyToday: alreadyToday,
            negativeFeedback: negativeFeedback,
            lowConfidence: lowConfidence || weakSimpleRepeat
        )
    }

    private func applyDiversityPolicy(
        to sorted: [FoodPatternSuggestion],
        limit: Int
    ) -> [FoodPatternSuggestion] {
        guard limit > 0 else { return [] }
        let hasSubstantial = sorted.contains { isSubstantial($0.pattern) }
        var selected: [FoodPatternSuggestion] = []
        var deferred: [FoodPatternSuggestion] = []
        var liquidOnlyCount = 0
        var lowSubstantialityCount = 0

        for suggestion in sorted {
            let liquidOnly = isLiquidOnly(suggestion.pattern)
            let lowSubstantiality = isLowSubstantiality(suggestion.pattern)

            if liquidOnly && liquidOnlyCount >= 1 {
                deferred.append(suggestion)
                continue
            }
            if lowSubstantiality && lowSubstantialityCount >= 2 {
                deferred.append(suggestion)
                continue
            }
            if hasSubstantial && selected.isEmpty && lowSubstantiality {
                deferred.append(suggestion)
                continue
            }

            selected.append(suggestion)
            if liquidOnly { liquidOnlyCount += 1 }
            if lowSubstantiality { lowSubstantialityCount += 1 }
            if selected.count >= limit { break }
        }

        guard selected.count < limit else { return selected }
        for suggestion in deferred where !selected.contains(where: { $0.pattern.id == suggestion.pattern.id }) {
            let liquidOnly = isLiquidOnly(suggestion.pattern)
            let lowSubstantiality = isLowSubstantiality(suggestion.pattern)
            if liquidOnly && liquidOnlyCount >= 1 {
                continue
            }
            if lowSubstantiality && lowSubstantialityCount >= 2 {
                continue
            }
            selected.append(suggestion)
            if liquidOnly { liquidOnlyCount += 1 }
            if lowSubstantiality { lowSubstantialityCount += 1 }
            if selected.count >= limit { break }
        }
        return selected
    }

    private func isAlreadyLoggedToday(_ pattern: FoodPattern, context: FoodPatternRecommendationContext) -> Bool {
        let patternComponents = Set(pattern.componentProfile.map(\.canonicalName).filter { !$0.isEmpty })
        guard !patternComponents.isEmpty else { return false }
        return context.todayObservations.contains { observation in
            let observationComponents = Set(observation.components.map(\.canonicalName).filter { !$0.isEmpty })
            return observationComponents == patternComponents
        }
    }

    private func supportsSameDayRepeat(_ pattern: FoodPattern, context: FoodPatternRecommendationContext) -> Bool {
        let groupedByDay = Dictionary(grouping: pattern.observations) {
            Calendar.current.startOfDay(for: $0.loggedAt)
        }
        let repeatDays = groupedByDay.values.filter { $0.count > 1 }
        guard repeatDays.count >= 2 else { return false }

        let patternComponents = Set(pattern.componentProfile.map(\.canonicalName).filter { !$0.isEmpty })
        guard let lastToday = context.todayObservations
            .filter({ Set($0.components.map(\.canonicalName).filter { !$0.isEmpty }) == patternComponents })
            .map(\.loggedAt)
            .max()
        else {
            return true
        }

        let minutes = Calendar.current.dateComponents([.minute], from: lastToday, to: context.targetDate).minute ?? 0
        return minutes >= 120
    }

    private func patternConfidence(for pattern: FoodPattern) -> Double {
        let componentStability = componentStability(for: pattern)
        let macroStability = macroStability(for: pattern)
        let identity = (
            pattern.identityEvidence.averageComponentAgreement +
            pattern.identityEvidence.averageMacroCompatibility +
            pattern.identityEvidence.averageServingCompatibility
        ) / 3.0
        return min(max((componentStability + macroStability + identity) / 3.0, 0), 1)
    }

    private func practicalUtility(for pattern: FoodPattern) -> Double {
        let nutrition = pattern.nutritionProfile
        let componentCount = pattern.componentProfile.count
        let roleCount = Set(pattern.componentProfile.map(\.role)).count
        let calorieScore = min(Double(nutrition.medianCalories) / 650.0, 1)
        let proteinScore = min(nutrition.medianProteinGrams / 38.0, 1)
        let structureScore = min(Double(componentCount) / 3.0, 1)
        let roleDiversityScore = min(Double(roleCount) / 3.0, 1)
        let base = 0.34 * calorieScore
            + 0.30 * proteinScore
            + 0.22 * structureScore
            + 0.14 * roleDiversityScore
        return isLiquidOnly(pattern) ? min(base, 0.42) : min(max(base, 0), 1)
    }

    private func isSubstantial(_ pattern: FoodPattern) -> Bool {
        let nutrition = pattern.nutritionProfile
        let componentCount = pattern.componentProfile.count
        let hasMultipleFoodComponents = componentCount >= 2 && !isLiquidOnly(pattern)
        return nutrition.medianCalories >= 320 && nutrition.medianProteinGrams >= 14
            || nutrition.medianProteinGrams >= 22
            || hasMultipleFoodComponents && nutrition.medianCalories >= 260
    }

    private func isLowSubstantiality(_ pattern: FoodPattern) -> Bool {
        !isSubstantial(pattern)
    }

    private func isLiquidOnly(_ pattern: FoodPattern) -> Bool {
        !pattern.componentProfile.isEmpty && pattern.componentProfile.allSatisfy { $0.role == .drink }
    }

    private func componentStability(for pattern: FoodPattern) -> Double {
        guard pattern.observationCount > 0 else { return 0 }
        let coreComponents = pattern.componentProfile.filter { $0.observationCount >= max(1, pattern.observationCount / 2) }
        return min(Double(coreComponents.count) / Double(max(pattern.componentProfile.count, 1)), 1)
    }

    private func macroStability(for pattern: FoodPattern) -> Double {
        let nutrition = pattern.nutritionProfile
        let calorieRange = Double(nutrition.upperCaloriesBound - nutrition.lowerCaloriesBound)
        let proteinRange = nutrition.upperProteinBound - nutrition.lowerProteinBound
        let carbsRange = nutrition.upperCarbsBound - nutrition.lowerCarbsBound
        let fatRange = nutrition.upperFatBound - nutrition.lowerFatBound
        let calorieScore = 1 - min(calorieRange / Double(max(nutrition.medianCalories, 1)), 1)
        let proteinScore = 1 - min(proteinRange / max(nutrition.medianProteinGrams, 1), 1)
        let carbsScore = 1 - min(carbsRange / max(nutrition.medianCarbsGrams, 1), 1)
        let fatScore = 1 - min(fatRange / max(nutrition.medianFatGrams, 1), 1)
        return max(0, (calorieScore + proteinScore + carbsScore + fatScore) / 4)
    }

    private func negativeFeedbackPenalty(for pattern: FoodPattern, now: Date) -> Double {
        if pattern.feedbackProfile.timesShown >= 4,
           pattern.feedbackProfile.timesAccepted == 0,
           pattern.feedbackProfile.timesDismissed == 0 {
            return 1.0
        }
        guard pattern.feedbackProfile.timesDismissed > pattern.feedbackProfile.timesAccepted else { return 0 }
        guard let lastDismissedAt = pattern.feedbackProfile.lastDismissedAt else {
            return min(Double(pattern.feedbackProfile.timesDismissed) * 0.12, 0.5)
        }
        let hours = Double(Calendar.current.dateComponents([.hour], from: lastDismissedAt, to: now).hour ?? 999)
        return hours < 12 ? 1.0 : min(Double(pattern.feedbackProfile.timesDismissed) * 0.12, 0.5)
    }

    static func timeSupport(for pattern: FoodPattern, targetDate: Date) -> Double {
        let hour = Calendar.current.component(.hour, from: targetDate)
        let weights = [0: 1.0, 1: 0.75, 2: 0.45, 3: 0.20]
        let total = max(pattern.observationCount, 1)
        let weighted = weights.reduce(0.0) { partial, item in
            let offset = item.key
            let weight = item.value
            if offset == 0 {
                return partial + Double(pattern.timeProfile.hourCounts[safe: hour] ?? 0) * weight
            }
            let before = (hour - offset + 24) % 24
            let after = (hour + offset) % 24
            return partial
                + Double(pattern.timeProfile.hourCounts[safe: before] ?? 0) * weight
                + Double(pattern.timeProfile.hourCounts[safe: after] ?? 0) * weight
        }
        return min(weighted / Double(total), 1)
    }

    static func sessionSupport(for pattern: FoodPattern, context: FoodPatternRecommendationContext) -> Double {
        guard !context.currentSessionObservations.isEmpty else { return 0 }
        let patternComponents = Set(pattern.componentProfile.map(\.canonicalName).filter { !$0.isEmpty })
        guard !patternComponents.isEmpty else { return 0 }
        let currentComponentSets = context.currentSessionObservations.map {
            Set($0.components.map(\.canonicalName).filter { !$0.isEmpty })
        }
        if currentComponentSets.contains(where: { !$0.isEmpty && $0 == patternComponents }) {
            return 0
        }
        if currentComponentSets.contains(where: { !$0.isEmpty && $0.isSubset(of: patternComponents) && $0 != patternComponents }) {
            return min(max(Double(pattern.distinctDays) / 4.0, 0.55), 0.85)
        }

        let historicalSessions = Dictionary(
            grouping: context.observations.filter {
                guard let observedSessionID = $0.sessionID else { return false }
                return observedSessionID != context.sessionID
            },
            by: { $0.sessionID! }
        )
        var anchorSessionCount = 0
        var completionCount = 0
        for observations in historicalSessions.values {
            let sessionComponents = observations.map { Set($0.components.map(\.canonicalName).filter { !$0.isEmpty }) }
            guard currentComponentSets.allSatisfy({ current in
                sessionComponents.contains { componentSimilarity(lhs: current, rhs: $0) >= 0.67 }
            }) else {
                continue
            }
            anchorSessionCount += 1
            if sessionComponents.contains(where: { componentSimilarity(lhs: $0, rhs: patternComponents) >= 0.67 }) {
                completionCount += 1
            }
        }
        guard anchorSessionCount > 0 else { return 0 }
        return min(Double(completionCount) / Double(anchorSessionCount), 1)
    }

    private static func recencyScore(for pattern: FoodPattern, targetDate: Date) -> Double {
        let daysSinceLast = Double(max(Calendar.current.dateComponents([.day], from: pattern.lastObservedAt, to: targetDate).day ?? 0, 0))
        return max(0, 1 - min(daysSinceLast / 45.0, 1))
    }

    private static func dayTypeSupport(for pattern: FoodPattern, targetDate: Date) -> Double {
        let requestedWeekend = Calendar.current.isDateInWeekend(targetDate)
        let matching = requestedWeekend ? pattern.timeProfile.weekendCount : pattern.timeProfile.weekdayCount
        return min(Double(matching) / Double(max(pattern.observationCount, 1)), 1)
    }

    private static func componentSimilarity(lhs: Set<String>, rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }
}

private struct FoodPatternSuppressionReasons {
    let oneOff: Bool
    let alreadyToday: Bool
    let negativeFeedback: Bool
    let lowConfidence: Bool

    var isSuppressed: Bool {
        oneOff || alreadyToday || negativeFeedback || lowConfidence
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
