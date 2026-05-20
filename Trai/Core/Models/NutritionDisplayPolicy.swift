import Foundation

struct NutritionDisplayPolicy {
    struct CalorieState: Equatable {
        let consumed: Int
        let target: Int
        let remaining: Int
        let progress: Double
        let primaryValueText: String
        let secondaryText: String
    }

    struct MacroState: Equatable, Identifiable {
        let macro: MacroType
        let current: Double
        let target: Int
        let remaining: Double
        let progress: Double

        var id: MacroType { macro }

        var valueText: String {
            "\(Int(current))g"
        }

        var remainingText: String {
            return "\(Int(remaining))g left"
        }
    }

    static func calorieState(consumed: Int, target: Int) -> CalorieState {
        let target = max(target, 1)
        let progress = min(Double(consumed) / Double(target), 1.0)
        let remaining = max(target - consumed, 0)
        return CalorieState(
            consumed: consumed,
            target: target,
            remaining: remaining,
            progress: progress,
            primaryValueText: "\(consumed) / \(target)",
            secondaryText: "\(remaining) kcal remaining"
        )
    }

    static func macroStates(
        values: [MacroType: Double],
        targets: [MacroType: Int],
        enabledMacros: Set<MacroType>
    ) -> [MacroState] {
        MacroType.displayOrder
            .filter { enabledMacros.contains($0) }
            .map { macro in
                macroState(
                    macro: macro,
                    current: values[macro] ?? 0,
                    target: targets[macro]
                )
            }
    }

    static func macroState(macro: MacroType, current: Double, target: Int?) -> MacroState {
        let target = max(target ?? 1, 1)
        return MacroState(
            macro: macro,
            current: current,
            target: target,
            remaining: max(Double(target) - current, 0),
            progress: min(current / Double(target), 1.0)
        )
    }
}
