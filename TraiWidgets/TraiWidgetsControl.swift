//
//  TraiWidgetsControl.swift
//  TraiWidgets
//
//  Control Center widget for quick workout start
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Control Widget

struct TraiWidgetsControl: ControlWidget {
    static let kind: String = "com.trai.workout-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartWorkoutControlIntent()) {
                Label("Start Workout", systemImage: "figure.run")
            }
        }
        .displayName("Start Workout")
        .description("Quickly start a new workout session.")
    }
}

// MARK: - Control Intent

struct StartWorkoutControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let description: IntentDescription = "Opens Trai to start a new workout"

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // Set flag to open workout on app launch
        UserDefaults.standard.set("custom", forKey: "startWorkoutFromIntent")
        return .result(opensIntent: OpenURLIntent(URL(string: "trai://workout")!))
    }
}
