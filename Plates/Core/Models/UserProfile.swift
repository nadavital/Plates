import Foundation
import SwiftData

/// Represents the user's fitness profile and goals
@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var dateOfBirth: Date?
    var heightCm: Double?

    // Biometric data
    var gender: String = "notSpecified"
    var activityLevel: String = "moderate"
    var activityNotes: String = ""

    // Unit preferences
    var usesMetricWeight: Bool = true      // For body weight (scale)
    var usesMetricHeight: Bool = true
    var usesMetricExerciseWeight: Bool = true  // For exercise/lifting weights

    /// Goal type: "weightLoss", "muscleGain", "maintenance", etc.
    var goalType: String = "maintenance"
    var targetWeightKg: Double?
    var currentWeightKg: Double?

    // Additional context for AI
    var additionalGoalNotes: String = ""

    // Daily nutrition goals
    var dailyCalorieGoal: Int = 2000
    var dailyProteinGoal: Int = 150
    var dailyCarbsGoal: Int = 200
    var dailyFatGoal: Int = 65
    var dailyFiberGoal: Int = 30
    var dailySugarGoal: Int = 50

    // Macro tracking preferences (stored as JSON for CloudKit)
    var enabledMacrosJSON: String = ""

    // Training/Rest day calorie adjustments
    var trainingDayCalories: Int?
    var restDayCalories: Int?
    var isTrainingDay: Bool = false

    // Full nutrition plan storage (JSON)
    var savedPlanJSON: String?

    // Weight tracking for plan recalculation
    var lastWeightForPlanKg: Double?

    // MARK: - Workout Plan Storage

    /// Full workout plan stored as JSON
    var savedWorkoutPlanJSON: String?

    /// When the workout plan was generated
    var workoutPlanGeneratedAt: Date?

    /// Preferred workout days per week
    var preferredWorkoutDays: Int = 3

    /// Experience level: "beginner", "intermediate", "advanced"
    var workoutExperienceLevel: String = "beginner"

    /// Equipment access: "fullGym", "homeAdvanced", "homeBasic", "bodyweightOnly"
    var workoutEquipmentAccess: String = "fullGym"

    /// Preferred workout duration in minutes
    var workoutTimePerSession: Int = 45

    // Weekly check-in preferences
    /// Preferred check-in day (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
    var preferredCheckInDay: Int?
    var lastCheckInDate: Date?

    // AI-generated plan metadata
    var aiPlanRationale: String = ""
    var aiPlanGeneratedAt: Date?

    var createdAt: Date = Date()
    var hasCompletedOnboarding: Bool = false

    init() {}

    // MARK: - Computed Properties

    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }
}

// MARK: - Goal Type Helper

extension UserProfile {
    enum GoalType: String, CaseIterable, Identifiable {
        case loseWeight = "loseWeight"
        case loseFat = "loseFat"
        case buildMuscle = "buildMuscle"
        case recomposition = "recomposition"
        case maintenance = "maintenance"
        case performance = "performance"
        case health = "health"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .loseWeight: "Lose Weight"
            case .loseFat: "Lose Fat, Keep Muscle"
            case .buildMuscle: "Build Muscle"
            case .recomposition: "Body Recomposition"
            case .maintenance: "Maintain Weight"
            case .performance: "Athletic Performance"
            case .health: "General Health"
            }
        }

        var description: String {
            switch self {
            case .loseWeight: "Reduce overall body weight through calorie deficit"
            case .loseFat: "Maximize fat loss while preserving lean muscle mass"
            case .buildMuscle: "Build strength and muscle with a calorie surplus"
            case .recomposition: "Lose fat and build muscle simultaneously"
            case .maintenance: "Maintain your current weight and fitness level"
            case .performance: "Optimize nutrition for athletic performance"
            case .health: "Focus on balanced nutrition and overall wellness"
            }
        }

        var iconName: String {
            switch self {
            case .loseWeight: "arrow.down.circle.fill"
            case .loseFat: "flame.circle.fill"
            case .buildMuscle: "figure.strengthtraining.traditional"
            case .recomposition: "arrow.triangle.2.circlepath.circle.fill"
            case .maintenance: "equal.circle.fill"
            case .performance: "figure.run.circle.fill"
            case .health: "heart.circle.fill"
            }
        }
    }

    var goal: GoalType {
        get { GoalType(rawValue: goalType) ?? .maintenance }
        set { goalType = newValue.rawValue }
    }
}

// MARK: - Gender

extension UserProfile {
    enum Gender: String, CaseIterable, Identifiable {
        case male = "male"
        case female = "female"
        case notSpecified = "notSpecified"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .male: "Male"
            case .female: "Female"
            case .notSpecified: "Prefer not to say"
            }
        }
    }

    var genderValue: Gender {
        get { Gender(rawValue: gender) ?? .notSpecified }
        set { gender = newValue.rawValue }
    }
}

// MARK: - Activity Level

extension UserProfile {
    enum ActivityLevel: String, CaseIterable, Identifiable {
        case sedentary = "sedentary"
        case light = "light"
        case moderate = "moderate"
        case active = "active"
        case veryActive = "veryActive"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sedentary: "Sedentary"
            case .light: "Lightly Active"
            case .moderate: "Moderately Active"
            case .active: "Very Active"
            case .veryActive: "Extremely Active"
            }
        }

        var description: String {
            switch self {
            case .sedentary: "Little to no exercise, desk job"
            case .light: "Light exercise 1-3 days/week"
            case .moderate: "Moderate exercise 3-5 days/week"
            case .active: "Hard exercise 6-7 days/week"
            case .veryActive: "Athlete or very physical job"
            }
        }

        var multiplier: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .active: 1.725
            case .veryActive: 1.9
            }
        }
    }

    var activityLevelValue: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevel) ?? .moderate }
        set { activityLevel = newValue.rawValue }
    }
}

// MARK: - Training Day Helpers

extension UserProfile {
    /// Get the effective calorie goal based on training/rest day
    var effectiveCalorieGoal: Int {
        if isTrainingDay, let trainingCals = trainingDayCalories {
            return trainingCals
        } else if !isTrainingDay, let restCals = restDayCalories {
            return restCals
        }
        return dailyCalorieGoal
    }

    /// Check if weight has changed significantly since plan was created
    func shouldPromptForRecalculation(currentWeight: Double, threshold: Double = 2.0) -> Bool {
        guard let lastWeight = lastWeightForPlanKg else { return false }
        return abs(currentWeight - lastWeight) >= threshold
    }
}

// MARK: - Weekly Check-In Helpers

extension UserProfile {
    enum Weekday: Int, CaseIterable, Identifiable {
        case sunday = 0
        case monday = 1
        case tuesday = 2
        case wednesday = 3
        case thursday = 4
        case friday = 5
        case saturday = 6

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .sunday: "Sunday"
            case .monday: "Monday"
            case .tuesday: "Tuesday"
            case .wednesday: "Wednesday"
            case .thursday: "Thursday"
            case .friday: "Friday"
            case .saturday: "Saturday"
            }
        }

        var shortName: String {
            switch self {
            case .sunday: "Sun"
            case .monday: "Mon"
            case .tuesday: "Tue"
            case .wednesday: "Wed"
            case .thursday: "Thu"
            case .friday: "Fri"
            case .saturday: "Sat"
            }
        }
    }

}

// MARK: - Macro Tracking Preferences

extension UserProfile {
    /// The set of macros the user wants to track
    var enabledMacros: Set<MacroType> {
        get {
            if enabledMacrosJSON.isEmpty {
                return MacroType.defaultEnabled
            }
            return Set(jsonString: enabledMacrosJSON)
        }
        set {
            enabledMacrosJSON = newValue.jsonString
        }
    }

    /// Check if a specific macro is enabled for tracking
    func isMacroEnabled(_ macro: MacroType) -> Bool {
        enabledMacros.contains(macro)
    }

    /// Get the daily goal for a specific macro type
    func goalFor(_ macro: MacroType) -> Int {
        switch macro {
        case .protein: dailyProteinGoal
        case .carbs: dailyCarbsGoal
        case .fat: dailyFatGoal
        case .fiber: dailyFiberGoal
        case .sugar: dailySugarGoal
        }
    }

    /// Set the daily goal for a specific macro type
    func setGoal(_ value: Int, for macro: MacroType) {
        switch macro {
        case .protein: dailyProteinGoal = value
        case .carbs: dailyCarbsGoal = value
        case .fat: dailyFatGoal = value
        case .fiber: dailyFiberGoal = value
        case .sugar: dailySugarGoal = value
        }
    }

    /// Get enabled macros in display order
    var enabledMacrosOrdered: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }
}

// MARK: - Workout Plan Helpers

extension UserProfile {
    /// The user's current workout plan
    var workoutPlan: WorkoutPlan? {
        get {
            guard let json = savedWorkoutPlanJSON else { return nil }
            return WorkoutPlan.fromJSON(json)
        }
        set {
            savedWorkoutPlanJSON = newValue?.toJSON()
            if newValue != nil {
                workoutPlanGeneratedAt = Date()
            }
        }
    }

    /// Whether the user has a workout plan
    var hasWorkoutPlan: Bool {
        savedWorkoutPlanJSON != nil
    }

    /// Experience level as enum
    var workoutExperience: WorkoutPlanGenerationRequest.ExperienceLevel {
        get { WorkoutPlanGenerationRequest.ExperienceLevel(rawValue: workoutExperienceLevel) ?? .beginner }
        set { workoutExperienceLevel = newValue.rawValue }
    }

    /// Equipment access as enum
    var workoutEquipment: WorkoutPlanGenerationRequest.EquipmentAccess {
        get { WorkoutPlanGenerationRequest.EquipmentAccess(rawValue: workoutEquipmentAccess) ?? .fullGym }
        set { workoutEquipmentAccess = newValue.rawValue }
    }

    /// Build a workout plan generation request from profile data
    func buildWorkoutPlanRequest(
        workoutType: WorkoutPlanGenerationRequest.WorkoutType = .mixed,
        selectedWorkoutTypes: [WorkoutPlanGenerationRequest.WorkoutType]? = nil,
        preferredSplit: WorkoutPlanGenerationRequest.PreferredSplit? = nil,
        cardioTypes: [WorkoutPlanGenerationRequest.CardioType]? = nil,
        specificGoals: [String]? = nil,
        weakPoints: [String]? = nil,
        injuries: String? = nil,
        preferences: String? = nil
    ) -> WorkoutPlanGenerationRequest {
        WorkoutPlanGenerationRequest(
            name: name,
            age: age ?? 30,
            gender: genderValue,
            goal: goal,
            activityLevel: activityLevelValue,
            workoutType: workoutType,
            selectedWorkoutTypes: selectedWorkoutTypes,
            experienceLevel: workoutExperience,
            equipmentAccess: workoutEquipment,
            availableDays: preferredWorkoutDays,
            timePerWorkout: workoutTimePerSession,
            preferredSplit: preferredSplit,
            cardioTypes: cardioTypes,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: specificGoals,
            weakPoints: weakPoints,
            injuries: injuries,
            preferences: preferences
        )
    }
}
