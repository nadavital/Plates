import Foundation
import SwiftData

enum WorkoutDayTargetContext {
    static func dayInterval(containing date: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func hasWorkout(
        in interval: DateInterval,
        workoutSessions: [WorkoutSession],
        liveWorkouts: [LiveWorkout]
    ) -> Bool {
        workoutSessions.contains { interval.contains($0.loggedAt) }
            || liveWorkouts.contains { workout in
                interval.contains(workout.startedAt)
                    || workout.completedAt.map(interval.contains) == true
            }
    }

    static func hasWorkout(in interval: DateInterval, modelContext: ModelContext) -> Bool {
        let startDate = interval.start
        let endDate = interval.end

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { workout in
                workout.loggedAt >= startDate && workout.loggedAt < endDate
            }
        )
        sessionDescriptor.fetchLimit = 1
        if ((try? modelContext.fetch(sessionDescriptor)) ?? []).isEmpty == false {
            return true
        }

        var liveDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate { workout in
                (workout.startedAt >= startDate && workout.startedAt < endDate)
                    || (workout.completedAt != nil && workout.completedAt! >= startDate && workout.completedAt! < endDate)
            }
        )
        liveDescriptor.fetchLimit = 1
        return ((try? modelContext.fetch(liveDescriptor)) ?? []).isEmpty == false
    }
}
