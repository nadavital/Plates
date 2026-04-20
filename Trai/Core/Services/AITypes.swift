//
//  AITypes.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import Foundation

/// Response from Trai AI for food analysis
struct FoodAnalysis: Codable, Sendable {
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let servingSize: String?
    let confidence: String?
    let notes: String?
    let emoji: String?
    let components: [FoodAnalysisComponent]?
    let mealKind: String?

    /// Display emoji with fallback
    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    var rejectionReason: String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedName == "unclear food or drink" {
            return "model returned unclear sentinel"
        }

        if calories < 0 || proteinGrams < 0 || carbsGrams < 0 || fatGrams < 0 {
            return "negative calories or macros"
        }

        return nil
    }

    var shouldBeRejectedForLogging: Bool {
        rejectionReason != nil
    }
}

struct FoodAnalysisComponent: Codable, Sendable, Equatable {
    let id: String?
    let displayName: String
    let role: String?
    let quantity: Double?
    let unit: String?
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let confidence: String?

    init(
        id: String? = nil,
        displayName: String,
        role: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        confidence: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.confidence = confidence
    }
}

/// Result from chat-based food analysis (with optional meal logging)
struct ChatFoodAnalysisResult: Sendable {
    let message: String
    let suggestedFoodEntry: SuggestedFoodEntry?
}

/// Food entry suggested by AI for logging
struct SuggestedFoodEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let servingSize: String?
    let emoji: String?  // Relevant emoji for the food (☕, 🥗, 🍳, etc.)
    let loggedAtDateString: String?  // YYYY-MM-DD format if user specified a date
    let loggedAtTime: String?  // HH:mm format if user specified a time
    let components: [SuggestedFoodComponent]
    let mealKind: String?
    let notes: String?
    let confidence: String?
    let schemaVersion: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case calories
        case proteinGrams
        case carbsGrams
        case fatGrams
        case fiberGrams
        case sugarGrams
        case servingSize
        case emoji
        case loggedAtDateString
        case loggedAtTime
        case components
        case mealKind
        case notes
        case confidence
        case schemaVersion
    }

    /// Parse the logged date/time into a concrete Date in the current calendar.
    var loggedAtDate: Date? {
        let calendar = Calendar.current
        let baseDay: Date

        if let loggedAtDateString {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let parsedDate = dateFormatter.date(from: loggedAtDateString) else { return nil }
            baseDay = parsedDate
        } else if loggedAtTime != nil {
            baseDay = Date()
        } else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: baseDay)

        if let loggedAtTime {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = "HH:mm"
            guard let parsedTime = timeFormatter.date(from: loggedAtTime) else { return nil }
            let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
        } else {
            let nowComponents = calendar.dateComponents([.hour, .minute, .second], from: Date())
            components.hour = nowComponents.hour
            components.minute = nowComponents.minute
            components.second = nowComponents.second
        }

        return calendar.date(from: components)
    }

    /// Display emoji or default fork and knife
    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        servingSize: String?,
        emoji: String? = nil,
        loggedAtDateString: String? = nil,
        loggedAtTime: String? = nil,
        components: [SuggestedFoodComponent] = [],
        mealKind: String? = nil,
        notes: String? = nil,
        confidence: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.servingSize = servingSize
        self.emoji = emoji
        self.loggedAtDateString = loggedAtDateString
        self.loggedAtTime = loggedAtTime
        self.components = components
        self.mealKind = mealKind
        self.notes = notes
        self.confidence = confidence
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Int.self, forKey: .calories)
        proteinGrams = try container.decode(Double.self, forKey: .proteinGrams)
        carbsGrams = try container.decode(Double.self, forKey: .carbsGrams)
        fatGrams = try container.decode(Double.self, forKey: .fatGrams)
        fiberGrams = try container.decodeIfPresent(Double.self, forKey: .fiberGrams)
        sugarGrams = try container.decodeIfPresent(Double.self, forKey: .sugarGrams)
        servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        loggedAtDateString = try container.decodeIfPresent(String.self, forKey: .loggedAtDateString)
        loggedAtTime = try container.decodeIfPresent(String.self, forKey: .loggedAtTime)
        components = try container.decodeIfPresent([SuggestedFoodComponent].self, forKey: .components) ?? []
        mealKind = try container.decodeIfPresent(String.self, forKey: .mealKind)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

struct SuggestedFoodComponent: Codable, Sendable, Equatable, Hashable {
    let id: String
    let displayName: String
    let role: String?
    let quantity: Double?
    let unit: String?
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let confidence: String?

    nonisolated init(
        id: String = UUID().uuidString,
        displayName: String,
        role: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        confidence: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.confidence = confidence
    }
}

extension SuggestedFoodComponent {
    nonisolated init(component: FoodAnalysisComponent) {
        self.init(
            id: component.id ?? UUID().uuidString,
            displayName: component.displayName,
            role: component.role,
            quantity: component.quantity,
            unit: component.unit,
            calories: component.calories,
            proteinGrams: component.proteinGrams,
            carbsGrams: component.carbsGrams,
            fatGrams: component.fatGrams,
            fiberGrams: component.fiberGrams,
            sugarGrams: component.sugarGrams,
            confidence: component.confidence
        )
    }
}

/// Context provided to AI for fitness-aware responses
struct FitnessContext: Sendable {
    let userGoal: String
    let dailyCalorieGoal: Int
    let dailyProteinGoal: Int
    let todaysCalories: Int
    let todaysProtein: Double
    let recentWorkouts: [String]
    let currentWeight: Double?
    let targetWeight: Double?

    init(
        userGoal: String,
        dailyCalorieGoal: Int,
        dailyProteinGoal: Int,
        todaysCalories: Int,
        todaysProtein: Double,
        recentWorkouts: [String] = [],
        currentWeight: Double? = nil,
        targetWeight: Double? = nil
    ) {
        self.userGoal = userGoal
        self.dailyCalorieGoal = dailyCalorieGoal
        self.dailyProteinGoal = dailyProteinGoal
        self.todaysCalories = todaysCalories
        self.todaysProtein = todaysProtein
        self.recentWorkouts = recentWorkouts
        self.currentWeight = currentWeight
        self.targetWeight = targetWeight
    }
}

// MARK: - Suggested Food Edit

/// Represents a proposed edit to an existing food entry (needs user confirmation)
struct SuggestedFoodEdit: Codable, Sendable, Identifiable {
    let entryId: UUID
    let name: String
    let emoji: String?
    let changes: [FieldChange]

    var id: UUID { entryId }

    struct FieldChange: Codable, Sendable, Identifiable {
        var id: String { field }
        let field: String
        let fieldKey: String  // Internal key for applying (e.g., "calories", "proteinGrams")
        let oldValue: String
        let newValue: String
        let newNumericValue: Double?  // For applying the change
        let newStringValue: String?  // For string changes
    }

    /// Display emoji or default
    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    /// Summary of changes for display
    var changesSummary: String {
        changes.map { "\($0.field): \($0.oldValue) → \($0.newValue)" }.joined(separator: ", ")
    }
}

struct SuggestedFoodComponentEdit: Codable, Sendable, Identifiable {
    let entryId: UUID
    let name: String
    let emoji: String?
    let operations: [Operation]
    let beforeTotals: NutritionSnapshot
    let afterTotals: NutritionSnapshot

    var id: UUID { entryId }

    struct NutritionSnapshot: Codable, Sendable {
        let calories: Int
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double?
        let sugarGrams: Double?

        var summary: String {
            let protein = Int(proteinGrams.rounded())
            let carbs = Int(carbsGrams.rounded())
            let fat = Int(fatGrams.rounded())
            return "\(calories) kcal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat"
        }
    }

    struct Operation: Codable, Sendable, Identifiable {
        enum OperationType: String, Codable, Sendable {
            case remove
            case restore
            case setFraction = "set_fraction"
            case add
            case update
        }

        let id: String
        let type: OperationType
        let componentId: String?
        let componentName: String
        let fractionOfOriginal: Double?
        let componentPayload: LoggedFoodComponent?
        let summary: String

        var summaryLine: String {
            summary
        }
    }

    var displayEmoji: String {
        emoji ?? "🍽️"
    }

    var operationsSummary: String {
        operations.map(\.summaryLine).joined(separator: ", ")
    }
}

// MARK: - Plan Update Suggestion

/// Plan update suggested by AI for user confirmation
struct PlanUpdateSuggestionEntry: Codable, Sendable, Identifiable {
    var id: String {
        "\(calories ?? 0)-\(proteinGrams ?? 0)-\(carbsGrams ?? 0)-\(fatGrams ?? 0)-\(fiberGrams ?? 0)-\(sugarGrams ?? 0)-\(goal ?? "")"
    }
    let calories: Int?
    let proteinGrams: Int?
    let carbsGrams: Int?
    let fatGrams: Int?
    let fiberGrams: Int?
    let sugarGrams: Int?
    let goal: String?
    let rationale: String?

    /// Whether this suggestion contains any changes
    var hasChanges: Bool {
        calories != nil || proteinGrams != nil || carbsGrams != nil ||
        fatGrams != nil || fiberGrams != nil || sugarGrams != nil || goal != nil
    }

    /// Formatted goal display name
    var goalDisplayName: String? {
        guard let goal else { return nil }
        // Convert raw goal string to display name
        switch goal.lowercased().replacing("_", with: "") {
        case "loseweight": return "Lose Weight"
        case "losefat": return "Lose Fat, Keep Muscle"
        case "buildmuscle": return "Build Muscle"
        case "recomposition", "bodyrecomposition": return "Body Recomposition"
        case "maintenance", "maintainweight": return "Maintain Weight"
        case "performance", "athleticperformance": return "Athletic Performance"
        case "health", "generalhealth": return "General Health"
        default: return goal.replacing("_", with: " ").capitalized
        }
    }

    /// Create from function executor result
    init(
        calories: Int? = nil,
        proteinGrams: Int? = nil,
        carbsGrams: Int? = nil,
        fatGrams: Int? = nil,
        fiberGrams: Int? = nil,
        sugarGrams: Int? = nil,
        goal: String? = nil,
        rationale: String? = nil
    ) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.goal = goal
        self.rationale = rationale
    }
}

// MARK: - Workout Plan Suggestion

/// Workout plan update suggested by AI for user confirmation
struct WorkoutPlanSuggestionEntry: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let plan: WorkoutPlan
    let message: String
}

// MARK: - Suggested Workout Entry

/// Workout suggested by AI for user confirmation before starting
struct SuggestedWorkoutEntry: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let workoutType: String
    let targetMuscleGroups: [String]
    let exercises: [SuggestedExercise]
    let durationMinutes: Int
    let rationale: String

    struct SuggestedExercise: Codable, Sendable, Identifiable {
        var id: UUID = UUID()
        let name: String
        let sets: Int
        let reps: Int
        let weightKg: Double?
    }

    /// Summary for display
    var exercisesSummary: String {
        let count = exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }

    /// Muscle groups summary
    var muscleGroupsSummary: String {
        targetMuscleGroups.map { $0.capitalized }.joined(separator: ", ")
    }
}

// MARK: - Suggested Workout Log

/// Completed workout log suggested by AI for user confirmation before saving
struct SuggestedWorkoutLog: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let name: String?  // Trai-generated workout name
    let workoutType: String
    let durationMinutes: Int?
    let exercises: [LoggedExercise]
    let notes: String?

    struct LoggedExercise: Codable, Sendable, Identifiable {
        var id: UUID = UUID()
        let name: String
        let sets: [SetData]

        struct SetData: Codable, Sendable, Identifiable {
            var id: UUID = UUID()
            let reps: Int
            let weightKg: Double?

            /// Formatted weight in user's preferred unit
            func formattedWeight(useLbs: Bool) -> String? {
                guard let weight = weightKg, weight > 0 else { return nil }
                if useLbs {
                    let lbs = weight * 2.20462
                    return "\(Int(lbs)) lbs"
                } else {
                    return "\(Int(weight)) kg"
                }
            }
        }

        /// Total sets count
        var setCount: Int { sets.count }

        /// Summary string for display (e.g., "3×10" or "12, 10, 8")
        var setsSummary: String {
            guard !sets.isEmpty else { return "" }
            let allSameReps = sets.dropFirst().allSatisfy { $0.reps == sets.first?.reps }
            if allSameReps, let firstReps = sets.first?.reps {
                return "\(sets.count)×\(firstReps)"
            } else {
                return sets.map { "\($0.reps)" }.joined(separator: ", ")
            }
        }

        /// Weight summary (uses max weight)
        var maxWeightKg: Double? {
            sets.compactMap { $0.weightKg }.max()
        }

        /// Formatted weight in user's preferred unit
        func formattedWeight(useLbs: Bool) -> String? {
            guard let weight = maxWeightKg, weight > 0 else { return nil }
            if useLbs {
                let lbs = weight * 2.20462
                return "\(Int(lbs)) lbs"
            } else {
                return "\(Int(weight)) kg"
            }
        }
    }

    /// Display name for the workout (uses Trai-generated name or falls back to type)
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return workoutType.capitalized
    }

    /// Total sets across all exercises
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.setCount }
    }

    /// Summary for display
    var summary: String {
        var parts: [String] = []
        if !exercises.isEmpty {
            parts.append("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
            parts.append("\(totalSets) sets")
        }
        if let duration = durationMinutes, duration > 0 {
            parts.append("\(duration) min")
        }
        return parts.isEmpty ? workoutType.capitalized : parts.joined(separator: " • ")
    }

    /// Whether this is a strength workout
    var isStrength: Bool {
        if let mode = WorkoutMode(rawValue: workoutType.lowercased()) {
            return mode.supportsMuscleTargets
        }
        return ["strength", "weights", "lifting"].contains(workoutType.lowercased())
    }
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case invalidInput(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case accessDenied(String)
    case quotaExceeded(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .parsingError:
            return "Failed to parse AI response"
        case .accessDenied(let message):
            return message
        case .quotaExceeded(let message):
            return message
        }
    }
}

extension Error {
    var isUserCancelledRequest: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var aiUserFacingMessage: String? {
        switch self {
        case let aiServiceError as AIServiceError:
            switch aiServiceError {
            case .invalidInput(let message), .accessDenied(let message), .quotaExceeded(let message):
                return message
            default:
                return nil
            }
        case let backendError as BackendClientError:
            return backendError.localizedDescription
        default:
            return nil
        }
    }

    func aiUserFacingMessage(fallback: String) -> String {
        aiUserFacingMessage ?? fallback
    }
}
