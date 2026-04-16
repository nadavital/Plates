//
//  AppNotifications.swift
//  Trai
//
//  App-wide notification names for inter-component communication
//

import Foundation

extension Notification.Name {
    /// Posted when a live workout is completed
    /// UserInfo may contain: "workoutId" (UUID)
    static let workoutCompleted = Notification.Name("workoutCompleted")

    /// Posted when food is logged
    static let foodLogged = Notification.Name("foodLogged")

    /// Posted when weight is logged
    static let weightLogged = Notification.Name("weightLogged")

    /// Posted when coach memories are created, edited, or deactivated.
    static let coachMemoriesChanged = Notification.Name("coachMemoriesChanged")

    /// Posted when the app is transitioning to background and live workout edits should be flushed.
    static let liveWorkoutForceFlush = Notification.Name("liveWorkoutForceFlush")
}
