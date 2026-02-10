//
//  LiveActivityIntents.swift
//  Trai
//
//  App Intents for Live Activity buttons (Add Set, Toggle Pause)
//  Note: The actual intents are defined in TraiWidgets/AppIntent.swift
//  This file contains the main app's handling logic.
//

import Foundation

// MARK: - App Group Constants

/// Constants for Live Activity intent communication via App Groups
enum LiveActivityIntentKeys {
    static let suiteName = SharedStorageKeys.AppGroup.suiteName
    static let addSetTimestamp = SharedStorageKeys.AppGroup.liveActivityAddSetTimestamp
    static let togglePauseTimestamp = SharedStorageKeys.AppGroup.liveActivityTogglePauseTimestamp
}
