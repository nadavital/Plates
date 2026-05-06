import Foundation

struct FoodHabit: Identifiable, Sendable, Equatable {
    let id: String
    let signature: FoodHabitSignature
    let representativeTitle: String
    let emoji: String?
    let kind: FoodMemoryKind
    let observations: [FoodObservation]
    let componentProfile: [FoodHabitComponent]
    let nutritionProfile: FoodHabitNutritionProfile
    let servingProfile: FoodHabitServingProfile?
    let timeProfile: FoodHabitTimeProfile
    let feedbackProfile: FoodHabitFeedbackProfile
    let lastObservedAt: Date
    let distinctDays: Int
    let observationCount: Int
}

struct FoodHabitSignature: Hashable, Sendable {
    let canonicalComponents: [String]
    let normalizedNameKey: String?
    let macroBucket: String
}

struct FoodHabitComponent: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let displayName: String
    let canonicalName: String
    let role: FoodComponentRole
    let observationCount: Int
    let medianCalories: Int
    let medianProteinGrams: Double
    let medianCarbsGrams: Double
    let medianFatGrams: Double
}

struct FoodHabitNutritionProfile: Sendable, Equatable {
    let medianCalories: Int
    let medianProteinGrams: Double
    let medianCarbsGrams: Double
    let medianFatGrams: Double
    let medianFiberGrams: Double?
    let medianSugarGrams: Double?
    let lowerCaloriesBound: Int
    let upperCaloriesBound: Int
    let lowerProteinBound: Double
    let upperProteinBound: Double
}

struct FoodHabitServingProfile: Sendable, Equatable {
    let commonServingText: String?
    let commonQuantity: Double?
    let commonUnit: String?
}

struct FoodHabitTimeProfile: Sendable, Equatable {
    let hourCounts: [Int]
    let weekdayCount: Int
    let weekendCount: Int
    let sessionPositionCounts: [Int: Int]
}

struct FoodHabitFeedbackProfile: Sendable, Equatable {
    let timesShown: Int
    let timesAccepted: Int
    let timesDismissed: Int
    let lastDismissedAt: Date?
}

struct FoodHabitBuilder {
    func habits(from observations: [FoodObservation], memories: [FoodMemory] = []) -> [FoodHabit] {
        let observationsByBaseSignature = Dictionary(grouping: observations, by: baseSignature(for:))
        let memoryFeedback = feedbackByMemoryID(memories)

        return observationsByBaseSignature.flatMap { signature, groupedObservations in
            splitByMacroProfile(groupedObservations).compactMap { macroGroup in
                buildHabit(
                    observations: macroGroup,
                    baseSignature: signature,
                    feedbackByMemoryID: memoryFeedback
                )
            }
        }
        .sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.lastObservedAt > $1.lastObservedAt
        }
    }

    private func baseSignature(for observation: FoodObservation) -> [String] {
        let components = Array(Set(observation.components.map(\.canonicalName).filter { !$0.isEmpty })).sorted()
        if !components.isEmpty {
            return components
        }
        return observation.normalizedName.split(separator: " ").map(String.init).sorted()
    }

    private func splitByMacroProfile(_ observations: [FoodObservation]) -> [[FoodObservation]] {
        guard observations.count >= 4 else { return [observations] }
        let buckets = Dictionary(grouping: observations) { observation in
            macroBucket(calories: observation.calories, protein: observation.proteinGrams)
        }
        if buckets.count <= 1 {
            return [observations]
        }
        return buckets.values.sorted {
            ($0.first?.calories ?? 0) < ($1.first?.calories ?? 0)
        }
    }

    private func buildHabit(
        observations: [FoodObservation],
        baseSignature: [String],
        feedbackByMemoryID: [UUID: FoodHabitFeedbackProfile]
    ) -> FoodHabit? {
        guard let first = observations.first else { return nil }
        let sortedObservations = observations.sorted { $0.loggedAt < $1.loggedAt }
        let nutrition = FoodHabitNutritionProfile(
            medianCalories: medianInt(sortedObservations.map(\.calories)),
            medianProteinGrams: median(sortedObservations.map(\.proteinGrams)),
            medianCarbsGrams: median(sortedObservations.map(\.carbsGrams)),
            medianFatGrams: median(sortedObservations.map(\.fatGrams)),
            medianFiberGrams: medianOptional(sortedObservations.map(\.fiberGrams)),
            medianSugarGrams: medianOptional(sortedObservations.map(\.sugarGrams)),
            lowerCaloriesBound: sortedObservations.map(\.calories).min() ?? first.calories,
            upperCaloriesBound: sortedObservations.map(\.calories).max() ?? first.calories,
            lowerProteinBound: sortedObservations.map(\.proteinGrams).min() ?? first.proteinGrams,
            upperProteinBound: sortedObservations.map(\.proteinGrams).max() ?? first.proteinGrams
        )
        let signature = FoodHabitSignature(
            canonicalComponents: baseSignature,
            normalizedNameKey: baseSignature.isEmpty ? first.normalizedName : nil,
            macroBucket: macroBucket(calories: nutrition.medianCalories, protein: nutrition.medianProteinGrams)
        )
        let id = "components:\(baseSignature.joined(separator: "|"))|macro:\(signature.macroBucket)"
        let distinctDays = Set(sortedObservations.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count
        let feedback = aggregateFeedback(sortedObservations: sortedObservations, feedbackByMemoryID: feedbackByMemoryID)

        return FoodHabit(
            id: id,
            signature: signature,
            representativeTitle: representativeTitle(for: sortedObservations),
            emoji: sortedObservations.reversed().compactMap(\.emoji).first,
            kind: sortedObservations.contains { $0.kind == .meal } ? .meal : first.kind,
            observations: sortedObservations,
            componentProfile: componentProfile(for: sortedObservations),
            nutritionProfile: nutrition,
            servingProfile: servingProfile(for: sortedObservations),
            timeProfile: timeProfile(for: sortedObservations),
            feedbackProfile: feedback,
            lastObservedAt: sortedObservations.last?.loggedAt ?? first.loggedAt,
            distinctDays: distinctDays,
            observationCount: sortedObservations.count
        )
    }

    private func feedbackByMemoryID(_ memories: [FoodMemory]) -> [UUID: FoodHabitFeedbackProfile] {
        Dictionary(uniqueKeysWithValues: memories.compactMap { memory in
            guard let stats = memory.suggestionStats else { return nil }
            return (
                memory.id,
                FoodHabitFeedbackProfile(
                    timesShown: stats.timesShown,
                    timesAccepted: stats.timesAccepted,
                    timesDismissed: stats.timesDismissed,
                    lastDismissedAt: stats.lastDismissedAt
                )
            )
        })
    }

    private func aggregateFeedback(
        sortedObservations: [FoodObservation],
        feedbackByMemoryID: [UUID: FoodHabitFeedbackProfile]
    ) -> FoodHabitFeedbackProfile {
        let profiles = Set(sortedObservations.compactMap(\.linkedMemoryID)).compactMap { feedbackByMemoryID[$0] }
        return FoodHabitFeedbackProfile(
            timesShown: profiles.map(\.timesShown).reduce(0, +),
            timesAccepted: profiles.map(\.timesAccepted).reduce(0, +),
            timesDismissed: profiles.map(\.timesDismissed).reduce(0, +),
            lastDismissedAt: profiles.compactMap(\.lastDismissedAt).max()
        )
    }

    private func representativeTitle(for observations: [FoodObservation]) -> String {
        let grouped = Dictionary(grouping: observations, by: \.displayName)
        return grouped
            .map { title, values in (title, values.count, values.map(\.loggedAt).max() ?? .distantPast) }
            .sorted {
                if $0.1 != $1.1 {
                    return $0.1 > $1.1
                }
                return $0.2 > $1.2
            }
            .first?.0 ?? observations.last?.displayName ?? "Food"
    }

    private func componentProfile(for observations: [FoodObservation]) -> [FoodHabitComponent] {
        let allComponents = observations.flatMap(\.components)
        return Dictionary(grouping: allComponents, by: \.canonicalName).compactMap { canonicalName, components in
            guard !canonicalName.isEmpty, let first = components.first else { return nil }
            return FoodHabitComponent(
                id: canonicalName,
                displayName: first.displayName,
                canonicalName: canonicalName,
                role: dominantRole(components),
                observationCount: components.count,
                medianCalories: medianInt(components.map(\.calories)),
                medianProteinGrams: median(components.map(\.proteinGrams)),
                medianCarbsGrams: median(components.map(\.carbsGrams)),
                medianFatGrams: median(components.map(\.fatGrams))
            )
        }
        .sorted { $0.canonicalName < $1.canonicalName }
    }

    private func dominantRole(_ components: [FoodObservationComponent]) -> FoodComponentRole {
        Dictionary(grouping: components, by: \.role)
            .max { $0.value.count < $1.value.count }?
            .key ?? .other
    }

    private func servingProfile(for observations: [FoodObservation]) -> FoodHabitServingProfile? {
        let servingText = mode(observations.compactMap(\.servingText))
        let quantity = medianOptional(observations.map(\.servingQuantity))
        let unit = mode(observations.compactMap(\.servingUnit))
        guard servingText != nil || quantity != nil || unit != nil else { return nil }
        return FoodHabitServingProfile(commonServingText: servingText, commonQuantity: quantity, commonUnit: unit)
    }

    private func timeProfile(for observations: [FoodObservation]) -> FoodHabitTimeProfile {
        var hourCounts = Array(repeating: 0, count: 24)
        var weekdayCount = 0
        var weekendCount = 0
        var sessionPositionCounts: [Int: Int] = [:]

        for observation in observations {
            let components = Calendar.current.dateComponents([.hour, .weekday], from: observation.loggedAt)
            if let hour = components.hour, hour >= 0, hour < 24 {
                hourCounts[hour] += 1
            }
            if components.weekday == 1 || components.weekday == 7 {
                weekendCount += 1
            } else {
                weekdayCount += 1
            }
            sessionPositionCounts[observation.sessionOrder, default: 0] += 1
        }

        return FoodHabitTimeProfile(
            hourCounts: hourCounts,
            weekdayCount: weekdayCount,
            weekendCount: weekendCount,
            sessionPositionCounts: sessionPositionCounts
        )
    }

    private func macroBucket(calories: Int, protein: Double) -> String {
        "cal\(calories / 250)-protein\(Int(protein / 20))"
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func medianInt(_ values: [Int]) -> Int {
        Int(median(values.map(Double.init)).rounded())
    }

    private func medianOptional(_ values: [Double?]) -> Double? {
        let compactValues = values.compactMap { $0 }
        guard !compactValues.isEmpty else { return nil }
        return median(compactValues)
    }

    private func mode(_ values: [String]) -> String? {
        Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .max { $0.value.count < $1.value.count }?
            .key
    }
}
