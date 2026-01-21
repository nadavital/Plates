//
//  TraiWorkoutAttributes.swift
//  Trai
//
//  ActivityAttributes for Live Activity workout tracking
//

import ActivityKit
import Foundation

/// Attributes for the Trai workout Live Activity
struct TraiWorkoutAttributes: ActivityAttributes {
    /// Static content that doesn't change during the workout
    let workoutName: String
    let targetMuscles: [String]
    let startedAt: Date

    /// Dynamic content that updates during the workout
    struct ContentState: Codable, Hashable {
        let elapsedSeconds: Int
        let currentExercise: String?
        let completedSets: Int
        let totalSets: Int
        let heartRate: Int?
        let isPaused: Bool

        /// Formatted elapsed time string (MM:SS or H:MM:SS)
        var formattedTime: String {
            let hours = elapsedSeconds / 3600
            let minutes = (elapsedSeconds % 3600) / 60
            let seconds = elapsedSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// Progress as a fraction (0.0 to 1.0)
        var progress: Double {
            guard totalSets > 0 else { return 0 }
            return Double(completedSets) / Double(totalSets)
        }

        /// Sets display string (e.g., "8/12 sets")
        var setsDisplay: String {
            "\(completedSets)/\(totalSets) sets"
        }
    }
}

// MARK: - Live Activity Manager

/// Manages the Live Activity lifecycle for workouts
@MainActor @Observable
final class LiveActivityManager {
    private var currentActivity: Activity<TraiWorkoutAttributes>?

    /// Whether a Live Activity is currently running
    var isActivityActive: Bool {
        currentActivity != nil
    }

    /// Start a new Live Activity for a workout
    func startActivity(
        workoutName: String,
        targetMuscles: [String],
        startedAt: Date
    ) {
        // Check if Live Activities are supported and enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not enabled")
            return
        }

        let attributes = TraiWorkoutAttributes(
            workoutName: workoutName,
            targetMuscles: targetMuscles,
            startedAt: startedAt
        )

        let initialState = TraiWorkoutAttributes.ContentState(
            elapsedSeconds: 0,
            currentExercise: nil,
            completedSets: 0,
            totalSets: 0,
            heartRate: nil,
            isPaused: false
        )

        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("Live Activity started: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    /// Update the Live Activity with new state
    func updateActivity(
        elapsedSeconds: Int,
        currentExercise: String?,
        completedSets: Int,
        totalSets: Int,
        heartRate: Int?,
        isPaused: Bool
    ) {
        guard let activity = currentActivity else { return }

        let updatedState = TraiWorkoutAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            currentExercise: currentExercise,
            completedSets: completedSets,
            totalSets: totalSets,
            heartRate: heartRate,
            isPaused: isPaused
        )

        let content = ActivityContent(state: updatedState, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    /// End the Live Activity
    func endActivity(showSummary: Bool = true) {
        guard let activity = currentActivity else { return }

        Task {
            if showSummary {
                // Show final state briefly before dismissing
                await activity.end(nil, dismissalPolicy: .after(.now + 5))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
    }

    /// Cancel all active workout activities (cleanup)
    func cancelAllActivities() {
        Task {
            for activity in Activity<TraiWorkoutAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
    }
}
