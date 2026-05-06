import Foundation

struct FoodPatternIdentityScore: Sendable, Equatable {
    let value: Double
    let shouldMerge: Bool
    let componentAgreement: Double
    let macroCompatibility: Double
    let servingCompatibility: Double
    let nameSimilarity: Double
    let embeddingSimilarity: Double?
}

struct FoodPatternIdentityScorer {
    func identityScore(
        _ lhs: FoodObservation,
        _ rhs: FoodObservation,
        embeddingSimilarity: Double? = nil
    ) -> FoodPatternIdentityScore {
        let componentAgreement = componentAgreement(lhs, rhs)
        let macroCompatibility = macroCompatibility(lhs, rhs)
        let servingCompatibility = servingCompatibility(lhs, rhs)
        let nameSimilarity = tokenSimilarity(lhs.normalizedName, rhs.normalizedName)
        let componentCount = min(nonEmptyComponents(lhs).count, nonEmptyComponents(rhs).count)

        let weightedValue =
            0.40 * componentAgreement +
            0.28 * macroCompatibility +
            0.12 * servingCompatibility +
            0.12 * nameSimilarity +
            0.08 * (embeddingSimilarity ?? nameSimilarity)

        let shouldMerge: Bool
        if componentCount >= 2 {
            shouldMerge = componentAgreement >= 0.60 && macroCompatibility >= 0.62 && weightedValue >= 0.68
        } else if componentCount == 1 {
            let exactComponentMatch = componentAgreement >= 0.99
            let strongSemanticMatch = (embeddingSimilarity ?? 0) >= 0.82 || nameSimilarity >= 0.78
            shouldMerge = macroCompatibility >= 0.68 && (exactComponentMatch || strongSemanticMatch) && weightedValue >= 0.70
        } else {
            let strongSemanticMatch = (embeddingSimilarity ?? 0) >= 0.86 || nameSimilarity >= 0.84
            shouldMerge = macroCompatibility >= 0.72 && strongSemanticMatch && weightedValue >= 0.74
        }

        return FoodPatternIdentityScore(
            value: weightedValue,
            shouldMerge: shouldMerge,
            componentAgreement: componentAgreement,
            macroCompatibility: macroCompatibility,
            servingCompatibility: servingCompatibility,
            nameSimilarity: nameSimilarity,
            embeddingSimilarity: embeddingSimilarity
        )
    }

    private func nonEmptyComponents(_ observation: FoodObservation) -> Set<String> {
        Set(observation.components.map(\.canonicalName).filter { !$0.isEmpty })
    }

    private func componentAgreement(_ lhs: FoodObservation, _ rhs: FoodObservation) -> Double {
        let lhsComponents = nonEmptyComponents(lhs)
        let rhsComponents = nonEmptyComponents(rhs)
        guard !lhsComponents.isEmpty, !rhsComponents.isEmpty else { return 0 }
        return Double(lhsComponents.intersection(rhsComponents).count) / Double(lhsComponents.union(rhsComponents).count)
    }

    private func macroCompatibility(_ lhs: FoodObservation, _ rhs: FoodObservation) -> Double {
        let calorieScore = toleranceScore(
            lhs: Double(lhs.calories),
            rhs: Double(rhs.calories),
            absoluteTolerance: 160,
            relativeTolerance: 0.35
        )
        let proteinScore = toleranceScore(lhs: lhs.proteinGrams, rhs: rhs.proteinGrams, absoluteTolerance: 12, relativeTolerance: 0.45)
        let carbsScore = toleranceScore(lhs: lhs.carbsGrams, rhs: rhs.carbsGrams, absoluteTolerance: 18, relativeTolerance: 0.45)
        let fatScore = toleranceScore(lhs: lhs.fatGrams, rhs: rhs.fatGrams, absoluteTolerance: 10, relativeTolerance: 0.50)
        return (calorieScore + proteinScore + carbsScore + fatScore) / 4
    }

    private func toleranceScore(
        lhs: Double,
        rhs: Double,
        absoluteTolerance: Double,
        relativeTolerance: Double
    ) -> Double {
        let tolerance = max(absoluteTolerance, max(abs(lhs), abs(rhs)) * relativeTolerance)
        guard tolerance > 0 else { return lhs == rhs ? 1 : 0 }
        return max(0, 1 - abs(lhs - rhs) / tolerance)
    }

    private func servingCompatibility(_ lhs: FoodObservation, _ rhs: FoodObservation) -> Double {
        if let lhsUnit = lhs.servingUnit?.lowercased(), let rhsUnit = rhs.servingUnit?.lowercased(), lhsUnit == rhsUnit {
            if let lhsQuantity = lhs.servingQuantity, let rhsQuantity = rhs.servingQuantity {
                return toleranceScore(lhs: lhsQuantity, rhs: rhsQuantity, absoluteTolerance: 0.5, relativeTolerance: 0.40)
            }
            return 1
        }

        let lhsServing = lhs.servingText?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsServing = rhs.servingText?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsServing != nil || rhsServing != nil {
            return lhsServing == rhsServing ? 1 : 0.55
        }
        return 0.75
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        return Double(lhsTokens.intersection(rhsTokens).count) / Double(lhsTokens.union(rhsTokens).count)
    }
}
