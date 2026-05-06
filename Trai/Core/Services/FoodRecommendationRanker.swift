import Foundation

struct FoodRecommendationFeatures: Sendable, Equatable {
    let decayedFrequency: Double
    let distinctDayScore: Double
    let recencyScore: Double
    let hourSupport: Double
    let dayTypeSupport: Double
    let sessionSupport: Double
    let componentStability: Double
    let macroStability: Double
    let positiveFeedback: Double
    let negativeFeedbackPenalty: Double
    let usefulnessScore: Double
    let sourceBoost: Double
}

struct FoodRecommendationRankerDiagnostics: Sendable, Equatable {
    let suppressedOneOffCount: Int
    let suppressedAlreadyTodayCount: Int
    let suppressedNegativeFeedbackCount: Int
    let suppressedLowUsefulnessCount: Int
}

struct FoodRecommendationRanker {
    func rank(_ candidates: [FoodRecommendationCandidate], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        let filtered = candidates.filter { !suppressionReasons(for: $0, context: context).isSuppressed }
        let bestByHabit = Dictionary(grouping: filtered, by: \.habit.id).compactMap { _, candidates in
            candidates.max {
                score($0.features) < score($1.features)
            }
        }
        let sorted = bestByHabit.sorted {
            if score($0.features) != score($1.features) {
                return score($0.features) > score($1.features)
            }
            return $0.habit.lastObservedAt > $1.habit.lastObservedAt
        }
        return applyFamilyCaps(sorted, limit: context.limit)
    }

    func score(_ features: FoodRecommendationFeatures) -> Double {
        let rawScore =
            0.18 * features.decayedFrequency +
            0.14 * features.distinctDayScore +
            0.10 * features.recencyScore +
            0.18 * features.hourSupport +
            0.06 * features.dayTypeSupport +
            0.12 * features.sessionSupport +
            0.08 * features.componentStability +
            0.06 * features.macroStability +
            0.12 * features.usefulnessScore +
            0.06 * features.positiveFeedback +
            features.sourceBoost -
            features.negativeFeedbackPenalty
        return min(max(rawScore, 0), 1)
    }

    func diagnostics(
        for candidates: [FoodRecommendationCandidate],
        context: FoodRecommendationContext
    ) -> FoodRecommendationRankerDiagnostics {
        var oneOff = Set<String>()
        var alreadyToday = Set<String>()
        var negative = Set<String>()
        var lowUsefulness = Set<String>()

        for candidate in candidates {
            let reasons = suppressionReasons(for: candidate, context: context)
            if reasons.oneOff { oneOff.insert(candidate.habit.id) }
            if reasons.alreadyToday { alreadyToday.insert(candidate.habit.id) }
            if reasons.negativeFeedback { negative.insert(candidate.habit.id) }
            if reasons.lowUsefulness { lowUsefulness.insert(candidate.habit.id) }
        }

        return FoodRecommendationRankerDiagnostics(
            suppressedOneOffCount: oneOff.count,
            suppressedAlreadyTodayCount: alreadyToday.count,
            suppressedNegativeFeedbackCount: negative.count,
            suppressedLowUsefulnessCount: lowUsefulness.count
        )
    }

    private func suppressionReasons(
        for candidate: FoodRecommendationCandidate,
        context: FoodRecommendationContext
    ) -> SuppressionReasons {
        let habit = candidate.habit
        let recentMorningBeverageRepeat = FoodRecommendationSpecialCases.isRecentMorningBeverageRepeat(
            habit: habit,
            targetDate: context.targetDate
        )
        let recentCompleteMeal = candidate.source == .recentCompleteMeal
            && FoodRecommendationSpecialCases.isRecentCompleteMeal(habit: habit, targetDate: context.targetDate)
        let oneOff = !recentMorningBeverageRepeat
            && !recentCompleteMeal
            && (habit.distinctDays < 2 || habit.observationCount < 2)
        let staleLowEvidence = habit.distinctDays < 3
            && (Calendar.current.dateComponents([.day], from: habit.lastObservedAt, to: context.targetDate).day ?? 0) > 30
        let alreadyToday = isAlreadyLoggedToday(habit, context: context) && !supportsSameDayRepeat(habit, context: context)
        let negativeFeedback = candidate.features.negativeFeedbackPenalty >= 1.0
        let lowUtilityWeakContext = candidate.features.usefulnessScore < 0.50
            && candidate.features.hourSupport < 0.35
            && candidate.features.sessionSupport < 0.55
            && candidate.features.positiveFeedback < 0.20
        let lowUsefulness = !recentMorningBeverageRepeat && !recentCompleteMeal && (
            candidate.features.usefulnessScore < 0.25 && candidate.features.hourSupport < 0.55
                || candidate.features.usefulnessScore < 0.50
                    && candidate.features.sessionSupport < 0.55
                    && habit.distinctDays < 4
                || lowUtilityWeakContext
        )
        return SuppressionReasons(
            oneOff: oneOff || staleLowEvidence,
            alreadyToday: alreadyToday,
            negativeFeedback: negativeFeedback,
            lowUsefulness: lowUsefulness
        )
    }

    private func isAlreadyLoggedToday(_ habit: FoodHabit, context: FoodRecommendationContext) -> Bool {
        let habitComponents = Set(habit.signature.canonicalComponents)
        return context.todayObservations.contains { observation in
            let observationComponents = Set(observation.components.map(\.canonicalName))
            return !habitComponents.isEmpty && observationComponents == habitComponents
        }
    }

    private func supportsSameDayRepeat(_ habit: FoodHabit, context: FoodRecommendationContext) -> Bool {
        let groupedByDay = Dictionary(grouping: habit.observations) {
            Calendar.current.startOfDay(for: $0.loggedAt)
        }
        let repeatDays = groupedByDay.values.filter { $0.count > 1 }
        guard repeatDays.count >= 2 else { return false }
        guard let lastToday = context.todayObservations
            .filter({ Set($0.components.map(\.canonicalName)) == Set(habit.signature.canonicalComponents) })
            .map(\.loggedAt)
            .max()
        else {
            return true
        }
        let minutes = Calendar.current.dateComponents([.minute], from: lastToday, to: context.targetDate).minute ?? 0
        return minutes >= 120
    }

    private func applyFamilyCaps(_ candidates: [FoodRecommendationCandidate], limit: Int) -> [FoodRecommendationCandidate] {
        let hasCompleteMeal = candidates.contains { FoodRecommendationFeatureBuilder.usefulnessScore(for: $0.habit) >= 0.85 }
        guard hasCompleteMeal else { return candidates }

        var selected: [FoodRecommendationCandidate] = []
        var beverageCount = 0
        var lowUtilityNonMealCount = 0

        for candidate in candidates {
            if isLowUtilityBeverage(candidate.habit), selected.count < 3 {
                guard beverageCount == 0 else { continue }
                beverageCount += 1
            }
            if isLowUtilityNonMeal(candidate.habit), selected.count < 3 {
                guard lowUtilityNonMealCount == 0 else { continue }
                lowUtilityNonMealCount += 1
            }
            selected.append(candidate)
            if selected.count >= max(limit, 3) {
                break
            }
        }
        return selected
    }

    private func isLowUtilityBeverage(_ habit: FoodHabit) -> Bool {
        let title = habit.representativeTitle.lowercased()
        let hasDrinkRole = habit.componentProfile.contains { $0.role == .drink }
        let looksLikeCoffee = title.contains("latte") || title.contains("coffee") || title.contains("cappuccino")
        return (hasDrinkRole || looksLikeCoffee) && FoodRecommendationFeatureBuilder.usefulnessScore(for: habit) < 0.65
    }

    private func isLowUtilityNonMeal(_ habit: FoodHabit) -> Bool {
        !FoodRecommendationSpecialCases.isCompleteMeal(habit)
            && FoodRecommendationFeatureBuilder.usefulnessScore(for: habit) < 0.65
    }
}

private struct SuppressionReasons {
    let oneOff: Bool
    let alreadyToday: Bool
    let negativeFeedback: Bool
    let lowUsefulness: Bool

    var isSuppressed: Bool {
        oneOff || alreadyToday || negativeFeedback || lowUsefulness
    }
}
