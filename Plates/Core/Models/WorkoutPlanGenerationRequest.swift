//
//  WorkoutPlanGenerationRequest.swift
//  Plates
//
//  Request structure for generating a workout plan with user preferences
//

import Foundation

// MARK: - Plan Generation Request

struct WorkoutPlanGenerationRequest {
    let name: String
    let age: Int
    let gender: UserProfile.Gender
    let goal: UserProfile.GoalType
    let activityLevel: UserProfile.ActivityLevel

    // Core preferences
    let workoutType: WorkoutType              // Primary/derived type
    let selectedWorkoutTypes: [WorkoutType]?  // All types user explicitly selected
    let experienceLevel: ExperienceLevel?
    let equipmentAccess: EquipmentAccess?
    let availableDays: Int?  // nil = flexible/as available
    let timePerWorkout: Int

    // Conditional/optional preferences
    let preferredSplit: PreferredSplit?
    let cardioTypes: [CardioType]?

    // Custom/Other text inputs
    let customWorkoutType: String?
    let customExperience: String?
    let customEquipment: String?
    let customCardioType: String?

    // Open-ended from conversation
    let specificGoals: [String]?      // "I want to do a pull-up", "visible abs"
    let weakPoints: [String]?         // "shoulders are lagging", "weak core"
    let injuries: String?             // "bad knee", "lower back issues"
    let preferences: String?          // "I love deadlifts", "hate burpees"

    /// Whether cardio should be included in the plan
    var includesCardio: Bool {
        if let types = selectedWorkoutTypes {
            return types.contains(.cardio) || types.contains(.mixed) || types.contains(.hiit)
        }
        return workoutType == .cardio || workoutType == .mixed || workoutType == .hiit
    }

    // MARK: - Workout Type

    enum WorkoutType: String, CaseIterable, Identifiable, Codable {
        case strength = "strength"
        case cardio = "cardio"
        case hiit = "hiit"
        case flexibility = "flexibility"
        case mixed = "mixed"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: "Strength Training"
            case .cardio: "Cardio & Endurance"
            case .hiit: "HIIT & Conditioning"
            case .flexibility: "Yoga & Flexibility"
            case .mixed: "Mixed / Varied"
            }
        }

        var description: String {
            switch self {
            case .strength: "Build muscle and get stronger with weights"
            case .cardio: "Improve endurance with running, cycling, etc."
            case .hiit: "High-intensity intervals for fat loss and conditioning"
            case .flexibility: "Improve mobility and reduce stress"
            case .mixed: "A balanced mix of different training styles"
            }
        }

        var iconName: String {
            switch self {
            case .strength: "dumbbell.fill"
            case .cardio: "figure.run"
            case .hiit: "bolt.fill"
            case .flexibility: "figure.yoga"
            case .mixed: "square.grid.2x2"
            }
        }

        var shouldAskAboutSplit: Bool {
            self == .strength || self == .mixed
        }

        var shouldAskAboutCardioType: Bool {
            self == .cardio || self == .mixed
        }
    }

    // MARK: - Preferred Split

    enum PreferredSplit: String, CaseIterable, Identifiable, Codable {
        case pushPullLegs = "pushPullLegs"
        case upperLower = "upperLower"
        case fullBody = "fullBody"
        case broSplit = "broSplit"
        case letTraiDecide = "letTraiDecide"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pushPullLegs: "Push/Pull/Legs"
            case .upperLower: "Upper/Lower"
            case .fullBody: "Full Body"
            case .broSplit: "Body Part Split"
            case .letTraiDecide: "Let Trai Decide"
            }
        }

        var description: String {
            switch self {
            case .pushPullLegs: "Push muscles one day, pull the next, then legs"
            case .upperLower: "Alternate between upper and lower body"
            case .fullBody: "Train your whole body each session"
            case .broSplit: "One muscle group per day (chest day, back day, etc.)"
            case .letTraiDecide: "Trai will pick the best split for you"
            }
        }

        var iconName: String {
            switch self {
            case .pushPullLegs: "arrow.left.arrow.right"
            case .upperLower: "arrow.up.arrow.down"
            case .fullBody: "figure.strengthtraining.traditional"
            case .broSplit: "rectangle.split.3x1"
            case .letTraiDecide: "sparkles"
            }
        }
    }

    // MARK: - Cardio Type

    enum CardioType: String, CaseIterable, Identifiable, Codable {
        case running = "running"
        case cycling = "cycling"
        case swimming = "swimming"
        case rowing = "rowing"
        case walking = "walking"
        case stairClimber = "stairClimber"
        case elliptical = "elliptical"
        case jumpRope = "jumpRope"
        case anyCardio = "anyCardio"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .running: "Running"
            case .cycling: "Cycling"
            case .swimming: "Swimming"
            case .rowing: "Rowing"
            case .walking: "Walking"
            case .stairClimber: "Stair Climber"
            case .elliptical: "Elliptical"
            case .jumpRope: "Jump Rope"
            case .anyCardio: "Any / No Preference"
            }
        }

        var iconName: String {
            switch self {
            case .running: "figure.run"
            case .cycling: "figure.outdoor.cycle"
            case .swimming: "figure.pool.swim"
            case .rowing: "figure.rower"
            case .walking: "figure.walk"
            case .stairClimber: "figure.stair.stepper"
            case .elliptical: "figure.elliptical"
            case .jumpRope: "figure.jumprope"
            case .anyCardio: "heart.fill"
            }
        }
    }

    // MARK: - Equipment Access

    enum EquipmentAccess: String, CaseIterable, Identifiable {
        case fullGym = "fullGym"
        case homeAdvanced = "homeAdvanced"
        case homeBasic = "homeBasic"
        case bodyweightOnly = "bodyweightOnly"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fullGym: "Full Gym"
            case .homeAdvanced: "Home Gym (Advanced)"
            case .homeBasic: "Home Gym (Basic)"
            case .bodyweightOnly: "Bodyweight Only"
            }
        }

        var description: String {
            switch self {
            case .fullGym: "Access to all machines, barbells, dumbbells, cables"
            case .homeAdvanced: "Barbell, dumbbells, bench, pull-up bar"
            case .homeBasic: "Dumbbells and resistance bands"
            case .bodyweightOnly: "No equipment needed"
            }
        }

        var iconName: String {
            switch self {
            case .fullGym: "building.2"
            case .homeAdvanced: "dumbbell.fill"
            case .homeBasic: "figure.strengthtraining.functional"
            case .bodyweightOnly: "figure.walk"
            }
        }
    }

    // MARK: - Experience Level

    enum ExperienceLevel: String, CaseIterable, Identifiable {
        case beginner = "beginner"
        case intermediate = "intermediate"
        case advanced = "advanced"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .beginner: "Beginner"
            case .intermediate: "Intermediate"
            case .advanced: "Advanced"
            }
        }

        var description: String {
            switch self {
            case .beginner: "New to strength training or less than 6 months experience"
            case .intermediate: "6 months to 2 years of consistent training"
            case .advanced: "2+ years of serious training with good technique"
            }
        }

        var iconName: String {
            switch self {
            case .beginner: "1.circle.fill"
            case .intermediate: "2.circle.fill"
            case .advanced: "3.circle.fill"
            }
        }
    }

    // MARK: - Recommended Split

    /// Recommend a split type based on preferences, available days and experience
    var recommendedSplit: WorkoutPlan.SplitType {
        // If user chose a specific split, use it
        if let preferred = preferredSplit, preferred != .letTraiDecide {
            switch preferred {
            case .pushPullLegs: return .pushPullLegs
            case .upperLower: return .upperLower
            case .fullBody: return .fullBody
            case .broSplit: return .bodyPartSplit
            case .letTraiDecide: break
            }
        }

        // Otherwise recommend based on days and experience
        switch availableDays {
        case 2:
            return .fullBody
        case 3:
            return experienceLevel == .beginner ? .fullBody : .pushPullLegs
        case 4:
            return .upperLower
        case 5, 6:
            return experienceLevel == .advanced ? .bodyPartSplit : .pushPullLegs
        default:
            return .fullBody
        }
    }
}
