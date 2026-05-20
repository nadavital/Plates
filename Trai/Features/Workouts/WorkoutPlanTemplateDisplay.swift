//
//  WorkoutPlanTemplateDisplay.swift
//  Trai
//

import SwiftUI

extension WorkoutPlan.WorkoutTemplate {
    var displayAccentColor: Color {
        switch sessionType {
        case .strength:
            switch resolvedTargetMuscleGroups.first {
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
        if !primaryBlockSummary.isEmpty {
            return primaryBlockSummary
        }
        return sessionType.displayName
    }

    var displayWorkloadSummary: String {
        if exerciseCount > 0 {
            return "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")"
        }

        let blockCount = displayBlocks.count
        if blockCount > 1 {
            return "\(blockCount) blocks"
        }

        if let block = displayBlocks.first {
            return block.kind.displayName
        }

        return sessionType.displayName
    }
}
