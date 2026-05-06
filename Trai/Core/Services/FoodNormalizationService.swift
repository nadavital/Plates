import Foundation

struct FoodNormalizationService {
    struct NormalizedServing: Sendable {
        let quantity: Double?
        let unit: String?
    }

    private let stopwords: Set<String> = ["with", "and", "the", "a", "an", "of", "style"]
    private let descriptorTokens: Set<String> = [
        "grilled", "roasted", "baked", "fried", "crispy", "fresh", "homemade", "house",
        "signature", "classic", "loaded", "light", "spicy", "sweet", "savory", "seasoned",
        "shredded", "sliced", "chopped", "diced", "mixed"
    ]
    private let unitAliases: [String: String] = [
        "cups": "cup",
        "cup": "cup",
        "oz": "ounce",
        "ounce": "ounce",
        "ounces": "ounce",
        "lb": "pound",
        "lbs": "pound",
        "pound": "pound",
        "pounds": "pound",
        "g": "gram",
        "gram": "gram",
        "grams": "gram",
        "kg": "kilogram",
        "kilogram": "kilogram",
        "kilograms": "kilogram",
        "ml": "milliliter",
        "milliliter": "milliliter",
        "milliliters": "milliliter",
        "l": "liter",
        "liter": "liter",
        "liters": "liter",
        "tbsp": "tablespoon",
        "tablespoon": "tablespoon",
        "tablespoons": "tablespoon",
        "tsp": "teaspoon",
        "teaspoon": "teaspoon",
        "teaspoons": "teaspoon",
        "servings": "serving",
        "serving": "serving",
        "bowls": "bowl",
        "bowl": "bowl",
        "plates": "plate",
        "plate": "plate",
        "bottles": "bottle",
        "bottle": "bottle",
        "cans": "can",
        "can": "can",
        "packs": "pack",
        "pack": "pack",
        "packets": "packet",
        "packet": "packet",
        "scoops": "scoop",
        "scoop": "scoop",
        "pieces": "piece",
        "piece": "piece",
        "slices": "slice",
        "slice": "slice"
    ]
    private let synonymMap: [String: String] = [
        "veggies": "vegetable",
        "veg": "vegetable",
        "greens": "green",
        "fries": "fry",
        "taters": "potato",
        "yoghurt": "yogurt",
        "garbanzos": "chickpea",
        "chickpeas": "chickpea"
    ]

    func normalizeFoodName(_ name: String) -> String {
        normalizedTokens(from: name).joined(separator: " ")
    }

    func normalizeComponentName(_ name: String) -> String {
        let componentDescriptors: Set<String> = [
            "grilled", "roasted", "baked", "fried", "crispy", "fresh", "homemade", "house",
            "seasoned", "shredded", "sliced", "chopped", "diced", "mixed", "white", "brown",
            "breast", "thigh", "lean", "low", "fat", "whole", "plain", "large", "small",
            "medium", "bowl", "plate", "serving", "side"
        ]
        let tokens = normalizedTokens(from: name).filter { !componentDescriptors.contains($0) }
        let drinkTokens: Set<String> = ["coffee", "latte", "cappuccino"]
        if tokens.contains("milk"), !drinkTokens.isDisjoint(with: tokens) {
            let withoutMilk = tokens.filter { $0 != "milk" }
            if !withoutMilk.isEmpty {
                return withoutMilk.joined(separator: " ")
            }
        }
        return tokens.isEmpty ? normalizeFoodName(name) : tokens.joined(separator: " ")
    }

    func canonicalComponentSignature(for components: [AcceptedFoodComponent]) -> [String] {
        Array(Set(components.map {
            let canonicalName = normalizeComponentName($0.displayName)
            return canonicalName.isEmpty ? $0.normalizedName : canonicalName
        }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    func aliasCandidates(for name: String) -> [String] {
        let tokens = normalizedTokens(from: name)
        guard !tokens.isEmpty else { return [] }

        var variants: [[String]] = [tokens]
        let withoutDescriptors = tokens.filter { !descriptorTokens.contains($0) }
        if !withoutDescriptors.isEmpty, withoutDescriptors != tokens {
            variants.append(withoutDescriptors)
        }

        let withoutContainers = withoutDescriptors.filter { !isContainerToken($0) }
        if withoutContainers.count >= 2, withoutContainers != withoutDescriptors {
            variants.append(withoutContainers)
        }

        let sortedMeaningfulTokens = withoutDescriptors.sorted()
        if sortedMeaningfulTokens != withoutDescriptors {
            variants.append(sortedMeaningfulTokens)
        }

        var results: [String] = []
        var seen = Set<String>()
        for variant in variants {
            let alias = variant.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, seen.insert(alias).inserted else { continue }
            results.append(alias)
        }
        return results
    }

    func normalizeServing(
        quantity: Double?,
        unit: String?,
        text: String?
    ) -> NormalizedServing {
        if let quantity, quantity > 0 {
            return NormalizedServing(
                quantity: quantity,
                unit: canonicalUnit(from: unit) ?? parsedUnit(from: text)
            )
        }

        guard let text else {
            return NormalizedServing(quantity: nil, unit: canonicalUnit(from: unit))
        }

        let trimmed = text
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NormalizedServing(quantity: nil, unit: canonicalUnit(from: unit))
        }

        let tokens = trimmed.split(separator: " ").map(String.init)
        guard let first = tokens.first else {
            return NormalizedServing(quantity: nil, unit: canonicalUnit(from: unit))
        }

        let parsedQuantity = parsedQuantityToken(first)
        let parsedUnit = tokens.dropFirst().lazy.compactMap(canonicalUnit(from:)).first

        return NormalizedServing(
            quantity: parsedQuantity,
            unit: canonicalUnit(from: unit) ?? parsedUnit
        )
    }

    func mealTimeBucket(for date: Date) -> MealTimeBucket {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        case 21..<24, 0..<5: return .lateNight
        default: return .snack
        }
    }

    func confidence(from rawValue: String?) -> FoodAnalysisConfidence? {
        guard let rawValue else { return nil }
        return FoodAnalysisConfidence(rawValue: rawValue.lowercased())
    }

    func componentRole(from rawValue: String?) -> FoodComponentRole {
        guard let rawValue else { return .other }
        return FoodComponentRole(rawValue: rawValue.lowercased()) ?? .other
    }

    private func normalizedTokens(from text: String) -> [String] {
        let lowercased = text.lowercased()
        let replaced = lowercased
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "w/", with: " with ")

        return replaced
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .filter { token in !token.allSatisfy { $0.isNumber } }
            .map(normalizeToken)
            .filter { !$0.isEmpty }
    }

    private func normalizeToken(_ token: String) -> String {
        let stripped = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "" }

        if let synonym = synonymMap[stripped] {
            return synonym
        }

        switch stripped {
        case let value where stopwords.contains(value):
            return ""
        case let value where value.hasSuffix("ies") && value.count > 3:
            return String(value.dropLast(3)) + "y"
        case let value where value.hasSuffix("s") && value.count > 3:
            return String(value.dropLast())
        default:
            return stripped
        }
    }

    private func canonicalUnit(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.allSatisfy(\.isNumber) else { return nil }
        return unitAliases[normalized] ?? normalizeToken(normalized)
    }

    private func parsedQuantityToken(_ token: String) -> Double? {
        if let direct = Double(token) {
            return direct
        }

        let pieces = token.split(separator: "/")
        if pieces.count == 2,
           let numerator = Double(pieces[0]),
           let denominator = Double(pieces[1]),
           denominator != 0 {
            return numerator / denominator
        }

        switch token {
        case "half":
            return 0.5
        case "quarter":
            return 0.25
        default:
            return nil
        }
    }

    private func parsedUnit(from text: String?) -> String? {
        guard let text else { return nil }
        let tokens = text
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        return tokens.compactMap(canonicalUnit(from:)).first
    }

    private func isContainerToken(_ token: String) -> Bool {
        switch token {
        case "bowl", "plate", "salad", "sandwich", "wrap", "taco", "burrito", "burger", "pizza", "pasta", "shake", "smoothie":
            return true
        default:
            return false
        }
    }
}
