import Foundation

struct FoodRecommendationCandidateGeneratorSet {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        var candidates: [FoodRecommendationCandidate] = []
        candidates += RepeatStapleFoodCandidateGenerator().candidates(habits: habits, context: context)
        candidates += TimeContextFoodCandidateGenerator().candidates(habits: habits, context: context)
        candidates += SessionCompletionFoodCandidateGenerator().candidates(habits: habits, context: context)
        candidates += SemanticVariantFoodCandidateGenerator().candidates(habits: habits, context: context)
        candidates += RecentRepeatedFoodCandidateGenerator().candidates(habits: habits, context: context)
        candidates += RecentCompleteMealFoodCandidateGenerator().candidates(habits: habits, context: context)
        return candidates
    }
}

struct RepeatStapleFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        habits
            .filter { $0.distinctDays >= 2 && $0.observationCount >= 2 }
            .map { candidate(habit: $0, source: .repeatStaple, context: context, sourceBoost: 0.08) }
    }
}

struct TimeContextFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        return habits.compactMap { habit -> FoodRecommendationCandidate? in
            let support = FoodRecommendationFeatureBuilder.hourSupport(for: habit, targetDate: context.targetDate)
            guard habit.distinctDays >= 2, support >= 0.20 else { return nil }
            return candidate(habit: habit, source: .timeContext, context: context, sourceBoost: support * 0.08)
        }
    }
}

struct SessionCompletionFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        guard !context.currentSessionObservations.isEmpty else { return [] }
        return habits.compactMap { habit in
            let support = FoodRecommendationFeatureBuilder.sessionCompletionSupport(for: habit, context: context)
            guard support > 0 else { return nil }
            return candidate(habit: habit, source: .sessionCompletion, context: context, sourceBoost: min(0.18, support * 0.18))
        }
    }
}

struct SemanticVariantFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        habits.compactMap { habit -> FoodRecommendationCandidate? in
            guard habit.distinctDays >= 2 else { return nil }
            let componentStability = FoodRecommendationFeatureBuilder.componentStability(for: habit)
            let macroStability = FoodRecommendationFeatureBuilder.macroStability(for: habit)
            guard componentStability >= 0.55, macroStability >= 0.45 else { return nil }
            return candidate(habit: habit, source: .semanticVariant, context: context, sourceBoost: 0.02)
        }
    }
}

struct RecentRepeatedFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        habits.compactMap { habit in
            guard habit.distinctDays >= 2
                || FoodRecommendationSpecialCases.isRecentMorningBeverageRepeat(habit: habit, targetDate: context.targetDate)
            else { return nil }
            let daysSinceLast = Calendar.current.dateComponents([.day], from: habit.lastObservedAt, to: context.targetDate).day ?? 999
            guard daysSinceLast <= 14 else { return nil }
            return candidate(habit: habit, source: .recentRepeated, context: context, sourceBoost: 0.04)
        }
    }
}

struct RecentCompleteMealFoodCandidateGenerator {
    func candidates(habits: [FoodHabit], context: FoodRecommendationContext) -> [FoodRecommendationCandidate] {
        let hasRepeatedCompleteMeal = habits.contains { habit in
            habit.distinctDays >= 2 && FoodRecommendationSpecialCases.isCompleteMeal(habit)
        }
        guard !hasRepeatedCompleteMeal else { return [] }

        let recentCompleteMealCandidates: [FoodRecommendationCandidate] = habits.compactMap { habit -> FoodRecommendationCandidate? in
            guard FoodRecommendationSpecialCases.isRecentCompleteMeal(habit: habit, targetDate: context.targetDate) else {
                return nil
            }
            let support = FoodRecommendationFeatureBuilder.hourSupport(for: habit, targetDate: context.targetDate)
            let sourceBoost = 0.12 + min(support * 0.08, 0.08)
            return candidate(habit: habit, source: .recentCompleteMeal, context: context, sourceBoost: sourceBoost)
        }
        return recentCompleteMealCandidates
    }
}

enum FoodRecommendationSpecialCases {
    static func isRecentCompleteMeal(habit: FoodHabit, targetDate: Date) -> Bool {
        guard isCompleteMeal(habit) else { return false }
        let daysSinceLast = Calendar.current.dateComponents([.day], from: habit.lastObservedAt, to: targetDate).day ?? 999
        guard daysSinceLast >= 0, daysSinceLast <= 21 else { return false }
        guard habit.nutritionProfile.medianCalories >= 300 || habit.componentProfile.count >= 2 else { return false }
        return true
    }

    static func isRecentMorningBeverageRepeat(habit: FoodHabit, targetDate: Date) -> Bool {
        let calendar = Calendar.current
        let targetHour = calendar.component(.hour, from: targetDate)
        guard (5..<10).contains(targetHour) else { return false }

        let title = habit.representativeTitle.lowercased()
        let isBeverage = habit.componentProfile.contains { $0.role == .drink }
            || title.contains("latte")
            || title.contains("coffee")
            || title.contains("cappuccino")
        guard isBeverage else { return false }

        let daysSinceLast = calendar.dateComponents([.day], from: habit.lastObservedAt, to: targetDate).day ?? 999
        guard daysSinceLast >= 0, daysSinceLast <= 3 else { return false }

        return FoodRecommendationFeatureBuilder.hourSupport(for: habit, targetDate: targetDate) >= 0.45
    }

    static func isCompleteMeal(_ habit: FoodHabit) -> Bool {
        let roles = Set(habit.componentProfile.map(\.role))
        let title = habit.representativeTitle.lowercased()
        let isBeverage = roles.contains(.drink)
            || title.contains("latte")
            || title.contains("coffee")
            || title.contains("cappuccino")
        let isConvenienceSnack = title.contains("protein bar")
            || (roles.contains(.mixed) && habit.componentProfile.count == 1 && habit.nutritionProfile.medianCalories < 350)
        guard !isBeverage && !isConvenienceSnack else { return false }

        let hasProtein = roles.contains(.protein) || habit.nutritionProfile.medianProteinGrams >= 20
        let hasMealBase = roles.contains(.carb)
            || roles.contains(.vegetable)
            || roles.contains(.fruit)
            || (roles.contains(.mixed) && habit.componentProfile.count >= 2)
        return (hasProtein && hasMealBase && (habit.componentProfile.count >= 2 || habit.nutritionProfile.medianCalories >= 450))
            || (habit.nutritionProfile.medianCalories >= 450 && habit.componentProfile.count >= 2)
    }
}

private func candidate(
    habit: FoodHabit,
    source: FoodRecommendationCandidateSource,
    context: FoodRecommendationContext,
    sourceBoost: Double
) -> FoodRecommendationCandidate {
    FoodRecommendationCandidate(
        habit: habit,
        source: source,
        features: FoodRecommendationFeatureBuilder.features(for: habit, sourceBoost: sourceBoost, context: context),
        suggestedEntry: FoodRecommendationFeatureBuilder.suggestedEntry(for: habit)
    )
}

enum FoodRecommendationFeatureBuilder {
    static func features(
        for habit: FoodHabit,
        sourceBoost: Double,
        context: FoodRecommendationContext
    ) -> FoodRecommendationFeatures {
        FoodRecommendationFeatures(
            decayedFrequency: decayedFrequency(for: habit, targetDate: context.targetDate),
            distinctDayScore: min(Double(habit.distinctDays) / 6.0, 1),
            recencyScore: recencyScore(for: habit, targetDate: context.targetDate),
            hourSupport: hourSupport(for: habit, targetDate: context.targetDate),
            dayTypeSupport: dayTypeSupport(for: habit, targetDate: context.targetDate),
            sessionSupport: sessionCompletionSupport(for: habit, context: context),
            componentStability: componentStability(for: habit),
            macroStability: macroStability(for: habit),
            positiveFeedback: positiveFeedback(for: habit),
            negativeFeedbackPenalty: negativeFeedbackPenalty(for: habit, now: context.now),
            usefulnessScore: usefulnessScore(for: habit),
            sourceBoost: sourceBoost
        )
    }

    static func suggestedEntry(for habit: FoodHabit) -> SuggestedFoodEntry {
        SuggestedFoodEntry(
            id: habit.id,
            name: habit.representativeTitle,
            calories: habit.nutritionProfile.medianCalories,
            proteinGrams: habit.nutritionProfile.medianProteinGrams,
            carbsGrams: habit.nutritionProfile.medianCarbsGrams,
            fatGrams: habit.nutritionProfile.medianFatGrams,
            fiberGrams: habit.nutritionProfile.medianFiberGrams,
            sugarGrams: habit.nutritionProfile.medianSugarGrams,
            servingSize: habit.servingProfile?.commonServingText,
            emoji: habit.emoji,
            components: habit.componentProfile.map {
                SuggestedFoodComponent(
                    id: $0.id,
                    displayName: $0.displayName,
                    role: $0.role.rawValue,
                    calories: $0.medianCalories,
                    proteinGrams: $0.medianProteinGrams,
                    carbsGrams: $0.medianCarbsGrams,
                    fatGrams: $0.medianFatGrams,
                    confidence: "medium"
                )
            },
            mealKind: habit.kind.rawValue,
            notes: "Built from foods you've logged before.",
            confidence: habit.distinctDays >= 3 ? "high" : "medium",
            schemaVersion: 2
        )
    }

    static func hourSupport(for habit: FoodHabit, targetDate: Date) -> Double {
        let hour = Calendar.current.component(.hour, from: targetDate)
        let weights = [0: 1.0, 1: 0.75, 2: 0.45, 3: 0.20]
        let total = max(habit.observationCount, 1)
        let weighted = weights.reduce(0.0) { partial, item in
            let offset = item.key
            let weight = item.value
            if offset == 0 {
                return partial + Double(habit.timeProfile.hourCounts[safe: hour] ?? 0) * weight
            }
            let before = (hour - offset + 24) % 24
            let after = (hour + offset) % 24
            return partial
                + Double(habit.timeProfile.hourCounts[safe: before] ?? 0) * weight
                + Double(habit.timeProfile.hourCounts[safe: after] ?? 0) * weight
        }
        return min(weighted / Double(total), 1)
    }

    static func componentStability(for habit: FoodHabit) -> Double {
        guard habit.observationCount > 0 else { return 0 }
        let coreComponents = habit.componentProfile.filter { $0.observationCount >= max(1, habit.observationCount / 2) }
        return min(Double(coreComponents.count) / Double(max(habit.signature.canonicalComponents.count, 1)), 1)
    }

    static func macroStability(for habit: FoodHabit) -> Double {
        let caloriesRange = Double(habit.nutritionProfile.upperCaloriesBound - habit.nutritionProfile.lowerCaloriesBound)
        let proteinRange = habit.nutritionProfile.upperProteinBound - habit.nutritionProfile.lowerProteinBound
        let calorieScore = 1 - min(caloriesRange / Double(max(habit.nutritionProfile.medianCalories, 1)), 1)
        let proteinScore = 1 - min(proteinRange / max(habit.nutritionProfile.medianProteinGrams, 1), 1)
        return max(0, (calorieScore + proteinScore) / 2)
    }

    static func usefulnessScore(for habit: FoodHabit) -> Double {
        let roles = Set(habit.componentProfile.map(\.role))
        let hasProtein = roles.contains(.protein) || habit.nutritionProfile.medianProteinGrams >= 20
        let hasCarbOrProduce = roles.contains(.carb) || roles.contains(.vegetable) || roles.contains(.fruit) || roles.contains(.mixed)
        let isBeverage = roles.contains(.drink) || habit.representativeTitle.lowercased().contains("latte")
            || habit.representativeTitle.lowercased().contains("coffee")
            || habit.representativeTitle.lowercased().contains("cappuccino")
        let isProteinBar = habit.representativeTitle.lowercased().contains("protein bar")

        if isProteinBar {
            return 0.45
        }
        if hasProtein && hasCarbOrProduce {
            return 1.0
        }
        if habit.nutritionProfile.medianCalories >= 450 && habit.componentProfile.count >= 2 {
            return 0.9
        }
        if isBeverage {
            return habit.nutritionProfile.medianProteinGrams >= 20 || habit.nutritionProfile.medianCalories >= 350 ? 0.55 : 0.20
        }
        if roles.contains(.fruit) || roles.contains(.vegetable) {
            return 0.55
        }
        return 0.40
    }

    static func sessionCompletionSupport(for habit: FoodHabit, context: FoodRecommendationContext) -> Double {
        guard !context.currentSessionObservations.isEmpty else { return 0 }
        let targetComponents = Set(habit.signature.canonicalComponents)
        guard !targetComponents.isEmpty else { return 0 }

        let currentComponentSets = context.currentSessionObservations.map {
            Set($0.components.map(\.canonicalName).filter { !$0.isEmpty })
        }
        guard currentComponentSets.allSatisfy({ !$0.isEmpty }) else { return 0 }
        if currentComponentSets.contains(where: { componentSimilarity(lhs: $0, rhs: targetComponents) >= 0.90 }) {
            return 0
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
        var immediateCompletionCount = 0

        for observations in historicalSessions.values {
            let sorted = observations.sorted {
                if $0.sessionOrder != $1.sessionOrder {
                    return $0.sessionOrder < $1.sessionOrder
                }
                return $0.loggedAt < $1.loggedAt
            }
            let anchorOrders = currentComponentSets.compactMap { currentComponents in
                sorted.first {
                    componentSimilarity(
                        lhs: Set($0.components.map(\.canonicalName).filter { !$0.isEmpty }),
                        rhs: currentComponents
                    ) >= 0.67
                }?.sessionOrder
            }
            guard anchorOrders.count == currentComponentSets.count, let lastAnchorOrder = anchorOrders.max() else {
                continue
            }
            anchorSessionCount += 1

            let completionOrders = sorted.compactMap { observation -> Int? in
                let observationComponents = Set(observation.components.map(\.canonicalName).filter { !$0.isEmpty })
                guard componentSimilarity(lhs: observationComponents, rhs: targetComponents) >= 0.67 else { return nil }
                guard observation.sessionOrder > lastAnchorOrder else { return nil }
                return observation.sessionOrder
            }
            guard let firstCompletionOrder = completionOrders.min() else { continue }
            completionCount += 1
            if firstCompletionOrder == lastAnchorOrder + 1 {
                immediateCompletionCount += 1
            }
        }

        let partialCurrentSupport = partialCurrentSessionSupport(
            for: habit,
            currentComponentSets: currentComponentSets,
            targetComponents: targetComponents
        )
        guard anchorSessionCount > 0 else { return partialCurrentSupport }
        let delayedCompletionCount = max(completionCount - immediateCompletionCount, 0)
        let weightedCompletions = Double(immediateCompletionCount) + Double(delayedCompletionCount) * 0.35
        return max(min(weightedCompletions / Double(anchorSessionCount), 1), partialCurrentSupport)
    }

    private static func decayedFrequency(for habit: FoodHabit, targetDate: Date) -> Double {
        let daysSinceLast = Double(max(Calendar.current.dateComponents([.day], from: habit.lastObservedAt, to: targetDate).day ?? 0, 0))
        let recencyDecay = exp(-daysSinceLast / 30.0)
        return min((Double(habit.observationCount) / 8.0) * recencyDecay, 1)
    }

    private static func recencyScore(for habit: FoodHabit, targetDate: Date) -> Double {
        let daysSinceLast = Double(max(Calendar.current.dateComponents([.day], from: habit.lastObservedAt, to: targetDate).day ?? 0, 0))
        return max(0, 1 - min(daysSinceLast / 45.0, 1))
    }

    private static func dayTypeSupport(for habit: FoodHabit, targetDate: Date) -> Double {
        let weekday = Calendar.current.component(.weekday, from: targetDate)
        let requestedWeekend = weekday == 1 || weekday == 7
        let matching = requestedWeekend ? habit.timeProfile.weekendCount : habit.timeProfile.weekdayCount
        return min(Double(matching) / Double(max(habit.observationCount, 1)), 1)
    }

    private static func positiveFeedback(for habit: FoodHabit) -> Double {
        min(Double(habit.feedbackProfile.timesAccepted) / 3.0, 1)
    }

    private static func negativeFeedbackPenalty(for habit: FoodHabit, now: Date) -> Double {
        if habit.feedbackProfile.timesShown >= 4,
           habit.feedbackProfile.timesAccepted == 0,
           habit.feedbackProfile.timesDismissed == 0 {
            return 1.0
        }
        guard habit.feedbackProfile.timesDismissed > habit.feedbackProfile.timesAccepted else { return 0 }
        guard let lastDismissedAt = habit.feedbackProfile.lastDismissedAt else {
            return min(Double(habit.feedbackProfile.timesDismissed) * 0.12, 0.5)
        }
        let hours = Double(Calendar.current.dateComponents([.hour], from: lastDismissedAt, to: now).hour ?? 999)
        return hours < 12 ? 1.0 : min(Double(habit.feedbackProfile.timesDismissed) * 0.12, 0.5)
    }

    private static func componentSimilarity(lhs: Set<String>, rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }

    private static func partialCurrentSessionSupport(
        for habit: FoodHabit,
        currentComponentSets: [Set<String>],
        targetComponents: Set<String>
    ) -> Double {
        guard habit.distinctDays >= 2, targetComponents.count >= 2 else { return 0 }
        let hasPartialAnchor = currentComponentSets.contains { currentComponents in
            guard !currentComponents.isEmpty, currentComponents.count < targetComponents.count else { return false }
            return currentComponents.isSubset(of: targetComponents)
        }
        guard hasPartialAnchor else { return 0 }
        return min(max(Double(habit.distinctDays) / 4.0, 0.55), 0.80)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
