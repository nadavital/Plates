import Foundation

struct FoodPatternEmbeddingDocument: Sendable, Equatable, Hashable {
    let title: String
    let aliases: [String]
    let components: [String]
    let serving: String?
    let nutritionBucket: String

    init(observation: FoodObservation) {
        title = observation.displayName
        aliases = [observation.normalizedName].filter { !$0.isEmpty }
        components = observation.components
            .map(\.canonicalName)
            .filter { !$0.isEmpty }
            .sorted()
        serving = observation.servingText
        nutritionBucket = Self.nutritionBucket(
            calories: observation.calories,
            protein: observation.proteinGrams,
            carbs: observation.carbsGrams,
            fat: observation.fatGrams
        )
    }

    var text: String {
        ([title] + aliases + components + [serving, nutritionBucket].compactMap { $0 })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " | ")
    }

    private static func nutritionBucket(calories: Int, protein: Double, carbs: Double, fat: Double) -> String {
        [
            "cal \(calories / 100 * 100)",
            "protein \(Int(protein / 10) * 10)",
            "carbs \(Int(carbs / 10) * 10)",
            "fat \(Int(fat / 5) * 5)"
        ].joined(separator: " ")
    }
}

protocol FoodPatternEmbeddingProvider: Sendable {
    func embedding(for document: FoodPatternEmbeddingDocument) async throws -> [Double]?
}
