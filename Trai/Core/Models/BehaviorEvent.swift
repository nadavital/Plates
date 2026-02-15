//
//  BehaviorEvent.swift
//  Trai
//
//  App-wide user behavior event log for adaptive personalization.
//

import Foundation
import SwiftData

enum BehaviorDomain: String, Codable, CaseIterable, Sendable {
    case nutrition
    case workout
    case body
    case reminder
    case planning
    case profile
    case engagement
    case general
}

enum BehaviorSurface: String, Codable, CaseIterable, Sendable {
    case dashboard
    case workouts
    case food
    case weight
    case chat
    case profile
    case widget
    case intent
    case system
}

enum BehaviorOutcome: String, Codable, CaseIterable, Sendable {
    case presented
    case performed
    case completed
    case suggestedTap
    case dismissed
    case opened
}

enum BehaviorActionKey {
    static let logFood = "nutrition.log_food"
    static let editFood = "nutrition.edit_food"
    static let logWeight = "body.log_weight"
    static let startWorkout = "workout.start"
    static let completeWorkout = "workout.complete"
    static let completeReminder = "reminder.complete"
    static let createReminder = "reminder.create"
    static let openCalorieDetail = "nutrition.open_calorie_detail"
    static let openMacroDetail = "nutrition.open_macro_detail"
    static let openWeight = "body.open_weight"
    static let openProfile = "profile.open_profile"
    static let openWorkouts = "workout.open_workouts"
    static let openWorkoutPlan = "workout.open_plan"
    static let openRecovery = "workout.open_recovery"
    static let reviewNutritionPlan = "planning.review_nutrition_plan"
    static let reviewWorkoutPlan = "planning.review_workout_plan"
    static let applyPlanUpdate = "planning.apply_plan_update"
}

@Model
final class BehaviorEvent {
    var id: UUID = UUID()
    var occurredAt: Date = Date()
    var actionKey: String = ""
    var domainRaw: String = BehaviorDomain.general.rawValue
    var surfaceRaw: String = BehaviorSurface.system.rawValue
    var outcomeRaw: String = BehaviorOutcome.performed.rawValue
    var relatedEntityId: String?
    var metadataJSON: String?

    init(
        actionKey: String,
        domain: BehaviorDomain,
        surface: BehaviorSurface,
        outcome: BehaviorOutcome,
        occurredAt: Date = .now,
        relatedEntityId: String? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = UUID()
        self.occurredAt = occurredAt
        self.actionKey = actionKey
        self.domainRaw = domain.rawValue
        self.surfaceRaw = surface.rawValue
        self.outcomeRaw = outcome.rawValue
        self.relatedEntityId = relatedEntityId
        self.metadataJSON = metadataJSON
    }

    var domain: BehaviorDomain {
        get { BehaviorDomain(rawValue: domainRaw) ?? .general }
        set { domainRaw = newValue.rawValue }
    }

    var surface: BehaviorSurface {
        get { BehaviorSurface(rawValue: surfaceRaw) ?? .system }
        set { surfaceRaw = newValue.rawValue }
    }

    var outcome: BehaviorOutcome {
        get { BehaviorOutcome(rawValue: outcomeRaw) ?? .performed }
        set { outcomeRaw = newValue.rawValue }
    }
}
