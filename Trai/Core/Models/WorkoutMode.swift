//
//  WorkoutMode.swift
//  Trai
//

import Foundation

enum WorkoutMode: String, Codable, CaseIterable, Identifiable {
    case strength = "strength"
    case cardio = "cardio"
    case hiit = "hiit"
    case climbing = "climbing"
    case yoga = "yoga"
    case pilates = "pilates"
    case flexibility = "flexibility"
    case mobility = "mobility"
    case mixed = "mixed"
    case recovery = "recovery"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .hiit: "HIIT"
        case .climbing: "Climbing"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .flexibility: "Flexibility"
        case .mobility: "Mobility"
        case .mixed: "Mixed"
        case .recovery: "Recovery"
        case .custom: "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        case .hiit: "bolt.heart.fill"
        case .climbing: "figure.climbing"
        case .yoga: "figure.yoga"
        case .pilates: "figure.flexibility"
        case .flexibility: "figure.cooldown"
        case .mobility: "figure.mind.and.body"
        case .mixed: "figure.mixed.cardio"
        case .recovery: "heart.text.square.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    var supportsMuscleTargets: Bool {
        switch self {
        case .strength, .mixed:
            return true
        case .cardio, .hiit, .climbing, .yoga, .pilates, .flexibility, .mobility, .recovery, .custom:
            return false
        }
    }

    var prefersStructuredEntries: Bool {
        switch self {
        case .strength, .mixed, .hiit:
            return true
        case .cardio, .climbing, .yoga, .pilates, .flexibility, .mobility, .recovery, .custom:
            return false
        }
    }

    var suggestedFocusPresets: [String] {
        switch self {
        case .strength:
            return ["Push", "Pull", "Legs", "Upper", "Full Body"]
        case .cardio:
            return ["Running", "Cycling", "Swimming", "Rowing", "Zone 2"]
        case .hiit:
            return ["Intervals", "Conditioning", "Sprints", "Circuit"]
        case .climbing:
            return ["Bouldering", "Top Rope", "Technique", "Endurance"]
        case .yoga:
            return ["Flow", "Recovery", "Balance", "Breathwork"]
        case .pilates:
            return ["Core", "Reformer", "Mat", "Control"]
        case .flexibility:
            return ["Stretching", "Range of Motion", "Cooldown", "Recovery"]
        case .mobility:
            return ["Hips", "Shoulders", "Thoracic", "Ankles"]
        case .mixed:
            return ["Strength", "Cardio", "Conditioning", "Full Body"]
        case .recovery:
            return ["Easy Cardio", "Mobility", "Breathing", "Walk"]
        case .custom:
            return ["Skills", "Technique", "Conditioning", "Recovery"]
        }
    }

    static func infer(from sessionName: String, focusAreas: [String], targetMuscleGroups: [String]) -> WorkoutMode {
        let tokens = ([sessionName] + focusAreas + targetMuscleGroups)
            .joined(separator: " ")
            .lowercased()

        if tokens.contains("yoga") { return .yoga }
        if tokens.contains("pilates") { return .pilates }
        if tokens.contains("climb") || tokens.contains("boulder") { return .climbing }
        if tokens.contains("hiit") || tokens.contains("interval") || tokens.contains("conditioning") { return .hiit }
        if tokens.contains("mobility") { return .mobility }
        if tokens.contains("flexibility") || tokens.contains("stretch") { return .flexibility }
        if tokens.contains("recovery") || tokens.contains("cooldown") { return .recovery }
        if tokens.contains("run")
            || tokens.contains("cycle")
            || tokens.contains("swim")
            || tokens.contains("row")
            || tokens.contains("cardio")
            || tokens.contains("walk")
            || tokens.contains("hike")
            || tokens.contains("stair")
            || tokens.contains("elliptical")
            || tokens.contains("jump rope")
            || tokens.contains("jumprope") {
            return .cardio
        }
        if !targetMuscleGroups.isEmpty { return .strength }
        return .custom
    }

    static func personalizedOrder(
        recentModes: [WorkoutMode] = [],
        plannedModes: [WorkoutMode] = [],
        goalModes: [WorkoutMode] = []
    ) -> [WorkoutMode] {
        var scores: [WorkoutMode: Int] = [:]

        for (index, mode) in recentModes.enumerated() {
            scores[mode, default: 0] += max(0, 90 - (index * 8))
        }

        for (index, mode) in plannedModes.enumerated() {
            scores[mode, default: 0] += max(0, 60 - (index * 6))
        }

        for mode in goalModes {
            scores[mode, default: 0] += 24
        }

        return allCases.sorted { lhs, rhs in
            let lhsScore = scores[lhs, default: 0]
            let rhsScore = scores[rhs, default: 0]
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.defaultSortIndex < rhs.defaultSortIndex
        }
    }

    private var defaultSortIndex: Int {
        switch self {
        case .strength: 0
        case .cardio: 1
        case .climbing: 2
        case .yoga: 3
        case .pilates: 4
        case .mobility: 5
        case .flexibility: 6
        case .hiit: 7
        case .mixed: 8
        case .recovery: 9
        case .custom: 10
        }
    }
}
