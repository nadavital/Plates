import CryptoKit
import Foundation

struct FoodPattern: Identifiable, Sendable, Equatable {
    let id: String
    let canonicalTitle: String
    let emoji: String?
    let observations: [FoodObservation]
    let aliases: [FoodPatternAlias]
    let componentProfile: [FoodPatternComponent]
    let nutritionProfile: FoodPatternNutritionProfile
    let servingProfile: FoodPatternServingProfile?
    let timeProfile: FoodPatternTimeProfile
    let sessionProfile: FoodPatternSessionProfile
    let feedbackProfile: FoodPatternFeedbackProfile
    let identityEvidence: FoodPatternIdentityEvidence
    let lastObservedAt: Date
    let distinctDays: Int
    let observationCount: Int
}

struct FoodPatternAlias: Sendable, Equatable, Hashable {
    let displayName: String
    let normalizedName: String
    let observationCount: Int
    let wasUserEdited: Bool
    let lastObservedAt: Date
}

struct FoodPatternComponent: Identifiable, Sendable, Equatable, Hashable {
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

struct FoodPatternNutritionProfile: Sendable, Equatable {
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
    let lowerCarbsBound: Double
    let upperCarbsBound: Double
    let lowerFatBound: Double
    let upperFatBound: Double
}

struct FoodPatternServingProfile: Sendable, Equatable {
    let commonServingText: String?
    let commonQuantity: Double?
    let commonUnit: String?
}

struct FoodPatternTimeProfile: Sendable, Equatable {
    let hourCounts: [Int]
    let weekdayCount: Int
    let weekendCount: Int
}

struct FoodPatternSessionProfile: Sendable, Equatable {
    let sessionPositionCounts: [Int: Int]
    let coOccurringComponentCounts: [String: Int]
    let coOccurringPatternIDs: [String: Int]
}

struct FoodPatternFeedbackProfile: Sendable, Equatable {
    let timesShown: Int
    let timesAccepted: Int
    let timesDismissed: Int
    let timesRefined: Int
    let lastDismissedAt: Date?
}

struct FoodPatternIdentityEvidence: Sendable, Equatable {
    let averageComponentAgreement: Double
    let averageMacroCompatibility: Double
    let averageServingCompatibility: Double
    let averageEmbeddingSimilarity: Double?
    let hasUserEditedObservation: Bool
    let representativeEntryIDs: [UUID]
}

struct FoodPatternBuilder {
    private let identityScorer = FoodPatternIdentityScorer()

    func patterns(from observations: [FoodObservation], memories: [FoodMemory] = []) -> [FoodPattern] {
        let sortedObservations = observations.sorted {
            if $0.loggedAt != $1.loggedAt {
                return $0.loggedAt < $1.loggedAt
            }
            return $0.sessionOrder < $1.sessionOrder
        }
        let memoryFeedback = feedbackByMemoryID(memories)

        var clusters: [[FoodObservation]] = []
        for observation in sortedObservations {
            if let index = bestClusterIndex(for: observation, clusters: clusters) {
                clusters[index].append(observation)
            } else {
                clusters.append([observation])
            }
        }

        let patterns = clusters.compactMap { cluster in
            buildPattern(observations: cluster, feedbackByMemoryID: memoryFeedback)
        }
        return patterns.sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.lastObservedAt > $1.lastObservedAt
        }
    }

    private func bestClusterIndex(for observation: FoodObservation, clusters: [[FoodObservation]]) -> Int? {
        var bestIndex: Int?
        var bestScore = 0.0

        for (index, cluster) in clusters.enumerated() {
            guard let representative = cluster.last else { continue }
            let score = identityScorer.identityScore(observation, representative)
            guard score.shouldMerge, score.value > bestScore else { continue }
            bestScore = score.value
            bestIndex = index
        }

        return bestIndex
    }

    private func buildPattern(
        observations: [FoodObservation],
        feedbackByMemoryID: [UUID: FoodPatternFeedbackProfile]
    ) -> FoodPattern? {
        guard let first = observations.first else { return nil }
        let sortedObservations = observations.sorted { $0.loggedAt < $1.loggedAt }
        let nutrition = FoodPatternNutritionProfile(
            medianCalories: medianInt(sortedObservations.map(\.calories)),
            medianProteinGrams: median(sortedObservations.map(\.proteinGrams)),
            medianCarbsGrams: median(sortedObservations.map(\.carbsGrams)),
            medianFatGrams: median(sortedObservations.map(\.fatGrams)),
            medianFiberGrams: medianOptional(sortedObservations.map(\.fiberGrams)),
            medianSugarGrams: medianOptional(sortedObservations.map(\.sugarGrams)),
            lowerCaloriesBound: sortedObservations.map(\.calories).min() ?? first.calories,
            upperCaloriesBound: sortedObservations.map(\.calories).max() ?? first.calories,
            lowerProteinBound: sortedObservations.map(\.proteinGrams).min() ?? first.proteinGrams,
            upperProteinBound: sortedObservations.map(\.proteinGrams).max() ?? first.proteinGrams,
            lowerCarbsBound: sortedObservations.map(\.carbsGrams).min() ?? first.carbsGrams,
            upperCarbsBound: sortedObservations.map(\.carbsGrams).max() ?? first.carbsGrams,
            lowerFatBound: sortedObservations.map(\.fatGrams).min() ?? first.fatGrams,
            upperFatBound: sortedObservations.map(\.fatGrams).max() ?? first.fatGrams
        )
        let components = componentProfile(for: sortedObservations)
        let id = patternID(components: components, fallbackName: first.normalizedName, nutrition: nutrition)
        let distinctDays = Set(sortedObservations.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count

        return FoodPattern(
            id: id,
            canonicalTitle: canonicalTitle(for: sortedObservations),
            emoji: sortedObservations.reversed().compactMap(\.emoji).first,
            observations: sortedObservations,
            aliases: aliases(for: sortedObservations),
            componentProfile: components,
            nutritionProfile: nutrition,
            servingProfile: servingProfile(for: sortedObservations),
            timeProfile: timeProfile(for: sortedObservations),
            sessionProfile: sessionProfile(for: sortedObservations),
            feedbackProfile: aggregateFeedback(sortedObservations: sortedObservations, feedbackByMemoryID: feedbackByMemoryID),
            identityEvidence: identityEvidence(for: sortedObservations),
            lastObservedAt: sortedObservations.last?.loggedAt ?? first.loggedAt,
            distinctDays: distinctDays,
            observationCount: sortedObservations.count
        )
    }

    private func patternID(
        components: [FoodPatternComponent],
        fallbackName: String,
        nutrition: FoodPatternNutritionProfile
    ) -> String {
        let componentKey = components.map(\.canonicalName).filter { !$0.isEmpty }.sorted().joined(separator: "|")
        let identityKey = componentKey.isEmpty ? fallbackName : componentKey
        let macroBucket = "cal\(nutrition.medianCalories / 250)-protein\(Int(nutrition.medianProteinGrams / 20))"
        return "pattern:\(identityKey)|\(macroBucket)"
    }

    private func canonicalTitle(for observations: [FoodObservation]) -> String {
        Dictionary(grouping: observations, by: \.displayName)
            .map { title, values in
                (
                    title,
                    values.count,
                    values.contains(where: \.wasUserEdited),
                    values.map(\.loggedAt).max() ?? .distantPast
                )
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.2 != $1.2 { return $0.2 && !$1.2 }
                return $0.3 > $1.3
            }
            .first?.0 ?? observations.last?.displayName ?? "Food"
    }

    private func aliases(for observations: [FoodObservation]) -> [FoodPatternAlias] {
        Dictionary(grouping: observations, by: \.normalizedName)
            .compactMap { normalizedName, values in
                guard let first = values.first else { return nil }
                let displayName = Dictionary(grouping: values, by: \.displayName)
                    .max { $0.value.count < $1.value.count }?
                    .key ?? first.displayName
                return FoodPatternAlias(
                    displayName: displayName,
                    normalizedName: normalizedName,
                    observationCount: values.count,
                    wasUserEdited: values.contains(where: \.wasUserEdited),
                    lastObservedAt: values.map(\.loggedAt).max() ?? first.loggedAt
                )
            }
            .sorted {
                if $0.observationCount != $1.observationCount {
                    return $0.observationCount > $1.observationCount
                }
                return $0.lastObservedAt > $1.lastObservedAt
            }
    }

    private func componentProfile(for observations: [FoodObservation]) -> [FoodPatternComponent] {
        let minimumCount = observations.count <= 2 ? 1 : max(2, Int(ceil(Double(observations.count) / 2.0)))
        return Dictionary(grouping: observations.flatMap(\.components), by: \.canonicalName)
            .compactMap { canonicalName, components in
                guard !canonicalName.isEmpty, components.count >= minimumCount, let first = components.first else { return nil }
                return FoodPatternComponent(
                    id: canonicalName,
                    displayName: mostRecentDisplayName(in: components) ?? first.displayName,
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

    private func mostRecentDisplayName(in components: [FoodObservationComponent]) -> String? {
        components.last?.displayName
    }

    private func dominantRole(_ components: [FoodObservationComponent]) -> FoodComponentRole {
        Dictionary(grouping: components, by: \.role)
            .max { $0.value.count < $1.value.count }?
            .key ?? .other
    }

    private func servingProfile(for observations: [FoodObservation]) -> FoodPatternServingProfile? {
        let servingText = mode(observations.compactMap(\.servingText))
        let quantity = medianOptional(observations.map(\.servingQuantity))
        let unit = mode(observations.compactMap(\.servingUnit))
        guard servingText != nil || quantity != nil || unit != nil else { return nil }
        return FoodPatternServingProfile(commonServingText: servingText, commonQuantity: quantity, commonUnit: unit)
    }

    private func timeProfile(for observations: [FoodObservation]) -> FoodPatternTimeProfile {
        var hourCounts = Array(repeating: 0, count: 24)
        var weekdayCount = 0
        var weekendCount = 0
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
        }
        return FoodPatternTimeProfile(hourCounts: hourCounts, weekdayCount: weekdayCount, weekendCount: weekendCount)
    }

    private func sessionProfile(for observations: [FoodObservation]) -> FoodPatternSessionProfile {
        var sessionPositionCounts: [Int: Int] = [:]
        for observation in observations {
            sessionPositionCounts[observation.sessionOrder, default: 0] += 1
        }
        return FoodPatternSessionProfile(
            sessionPositionCounts: sessionPositionCounts,
            coOccurringComponentCounts: [:],
            coOccurringPatternIDs: [:]
        )
    }

    private func identityEvidence(for observations: [FoodObservation]) -> FoodPatternIdentityEvidence {
        guard observations.count > 1 else {
            return FoodPatternIdentityEvidence(
                averageComponentAgreement: 1,
                averageMacroCompatibility: 1,
                averageServingCompatibility: 1,
                averageEmbeddingSimilarity: nil,
                hasUserEditedObservation: observations.contains(where: \.wasUserEdited),
                representativeEntryIDs: observations.map(\.entryID)
            )
        }

        var componentScores: [Double] = []
        var macroScores: [Double] = []
        var servingScores: [Double] = []
        for index in observations.indices.dropFirst() {
            let score = identityScorer.identityScore(observations[index], observations[index - 1])
            componentScores.append(score.componentAgreement)
            macroScores.append(score.macroCompatibility)
            servingScores.append(score.servingCompatibility)
        }

        return FoodPatternIdentityEvidence(
            averageComponentAgreement: average(componentScores),
            averageMacroCompatibility: average(macroScores),
            averageServingCompatibility: average(servingScores),
            averageEmbeddingSimilarity: nil,
            hasUserEditedObservation: observations.contains(where: \.wasUserEdited),
            representativeEntryIDs: observations.map(\.entryID)
        )
    }

    private func feedbackByMemoryID(_ memories: [FoodMemory]) -> [UUID: FoodPatternFeedbackProfile] {
        Dictionary(uniqueKeysWithValues: memories.compactMap { memory in
            guard let stats = memory.suggestionStats else { return nil }
            return (
                memory.id,
                FoodPatternFeedbackProfile(
                    timesShown: stats.timesShown,
                    timesAccepted: stats.timesAccepted,
                    timesDismissed: stats.timesDismissed,
                    timesRefined: stats.timesRefined,
                    lastDismissedAt: stats.lastDismissedAt
                )
            )
        })
    }

    private func aggregateFeedback(
        sortedObservations: [FoodObservation],
        feedbackByMemoryID: [UUID: FoodPatternFeedbackProfile]
    ) -> FoodPatternFeedbackProfile {
        let profiles = Set(sortedObservations.compactMap(\.linkedMemoryID)).compactMap { feedbackByMemoryID[$0] }
        return FoodPatternFeedbackProfile(
            timesShown: profiles.map(\.timesShown).reduce(0, +),
            timesAccepted: profiles.map(\.timesAccepted).reduce(0, +),
            timesDismissed: profiles.map(\.timesDismissed).reduce(0, +),
            timesRefined: profiles.map(\.timesRefined).reduce(0, +),
            lastDismissedAt: profiles.compactMap(\.lastDismissedAt).max()
        )
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

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

extension FoodPattern {
    var stableUUID: UUID {
        let digest = SHA256.hash(data: Data(id.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
