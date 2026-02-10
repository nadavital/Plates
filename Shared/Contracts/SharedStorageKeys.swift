//
//  SharedStorageKeys.swift
//  Shared
//
//  Cross-target storage keys used by app and widget extension.
//

import Foundation

enum SharedStorageKeys {
    enum AppGroup {
        static let suiteName = "group.com.nadav.trai"
        static let widgetData = "widgetData"
        static let pendingFoodLogs = "pendingFoodLogs"
        static let liveActivityAddSetTimestamp = "liveActivityAddSetTimestamp"
        static let liveActivityTogglePauseTimestamp = "liveActivityTogglePauseTimestamp"
    }

    enum LaunchIntents {
        static let openFoodCamera = "openFoodCameraFromIntent"
        static let startWorkout = "startWorkoutFromIntent"
    }
}
