import Foundation

struct FoodMemoryIndex {
    private let nameLookup: [String: [FoodMemory]]
    private let componentLookup: [String: [FoodMemory]]
    private let macroLookup: [String: [FoodMemory]]
    private let servingLookup: [String: [FoodMemory]]
    private let mealTimeLookup: [String: [FoodMemory]]

    init(memories: [FoodMemory]) {
        var nameLookup: [String: [FoodMemory]] = [:]
        var componentLookup: [String: [FoodMemory]] = [:]
        var macroLookup: [String: [FoodMemory]] = [:]
        var servingLookup: [String: [FoodMemory]] = [:]
        var mealTimeLookup: [String: [FoodMemory]] = [:]

        for memory in memories {
            let normalizedNameValues = Set(
                [memory.primaryNormalizedName]
                    + memory.aliases.map(\.normalizedName)
                    + memory.fingerprints
                        .filter { $0.type == .normalizedName }
                        .map(\.value)
            )

            for normalizedName in normalizedNameValues {
                for token in normalizedName.split(separator: " ").map(String.init) where !token.isEmpty {
                    nameLookup[token, default: []].append(memory)
                }
            }

            for component in memory.components {
                componentLookup[component.normalizedName, default: []].append(memory)
            }

            for fingerprint in memory.fingerprints where !fingerprint.value.isEmpty {
                switch fingerprint.type {
                case .coarseMacroBucket:
                    macroLookup[fingerprint.value, default: []].append(memory)
                case .servingSignature:
                    servingLookup[fingerprint.value, default: []].append(memory)
                case .mealTimeBucket:
                    mealTimeLookup[fingerprint.value, default: []].append(memory)
                default:
                    continue
                }
            }
        }

        self.nameLookup = nameLookup
        self.componentLookup = componentLookup
        self.macroLookup = macroLookup
        self.servingLookup = servingLookup
        self.mealTimeLookup = mealTimeLookup
    }

    func candidates(for snapshot: AcceptedFoodSnapshot) -> [FoodMemory] {
        let aliasTokens = Set(snapshot.nameAliases.flatMap { $0.split(separator: " ").map(String.init) })
        let componentNames = snapshot.components.map(\.normalizedName)
        let coarseMacroBucket = [
            "cal:\(Int((Double(snapshot.totalCalories) / 100).rounded() * 100))",
            "p:\(Int((snapshot.totalProteinGrams / 10).rounded() * 10))",
            "c:\(Int((snapshot.totalCarbsGrams / 10).rounded() * 10))",
            "f:\(Int((snapshot.totalFatGrams / 5).rounded() * 5))"
        ].joined(separator: "|")
        let servingSignature = if let quantity = snapshot.servingQuantity, let unit = snapshot.servingUnit {
            "\(Int((quantity * 10).rounded())):\(unit)"
        } else {
            ""
        }

        var candidatesById: [UUID: FoodMemory] = [:]

        for token in aliasTokens {
            for memory in nameLookup[token] ?? [] {
                candidatesById[memory.id] = memory
            }
        }

        for componentName in componentNames {
            for memory in componentLookup[componentName] ?? [] {
                candidatesById[memory.id] = memory
            }
        }

        for memory in macroLookup[coarseMacroBucket] ?? [] {
            candidatesById[memory.id] = memory
        }

        if !servingSignature.isEmpty {
            for memory in servingLookup[servingSignature] ?? [] {
                candidatesById[memory.id] = memory
            }
        }

        for memory in mealTimeLookup[snapshot.mealTimeBucket.rawValue] ?? [] {
            candidatesById[memory.id] = memory
        }

        return Array(candidatesById.values)
    }
}
