//
//  WorkoutPlanTemplateDisplay.swift
//  Trai
//

import SwiftUI

extension WorkoutPlan.WorkoutTemplate {
    var displayAccentColor: Color {
        switch sessionType {
        case .strength:
            switch targetMuscleGroups.first {
            case "chest", "shoulders", "triceps":
                return .orange
            case "back", "biceps":
                return .blue
            case "quads", "hamstrings", "glutes", "calves", "legs":
                return .green
            case "core":
                return .purple
            default:
                return .accentColor
            }
        case .cardio:
            return .cyan
        case .hiit:
            return .red
        case .climbing:
            return .brown
        case .yoga:
            return .indigo
        case .pilates:
            return .pink
        case .flexibility:
            return .teal
        case .mobility:
            return .purple
        case .mixed:
            return .accentColor
        case .recovery:
            return .mint
        case .custom:
            return .gray
        }
    }

    var displaySubtitle: String {
        if !focusAreasDisplay.isEmpty {
            return focusAreasDisplay
        }
        return sessionType.displayName
    }
}
