//
//  AllWorkoutsSheet.swift
//  Plates
//
//  Full workout history sheet showing all workouts grouped by date
//

import SwiftUI

// MARK: - All Workouts Sheet

struct AllWorkoutsSheet: View {
    let workoutsByDate: [(date: Date, workouts: [WorkoutSession])]
    let liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDelete: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    @Environment(\.dismiss) private var dismiss

    private var allDates: [Date] {
        let sessionDates = Set(workoutsByDate.map { $0.date })
        let liveDates = Set(liveWorkoutsByDate.map { $0.date })
        return sessionDates.union(liveDates).sorted(by: >)
    }

    private func sessions(for date: Date) -> [WorkoutSession] {
        workoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    private func liveWorkouts(for date: Date) -> [LiveWorkout] {
        liveWorkoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allDates, id: \.self) { date in
                    Section {
                        // LiveWorkouts first
                        ForEach(liveWorkouts(for: date)) { workout in
                            LiveWorkoutListRow(workout: workout) {
                                onLiveWorkoutTap(workout)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteLiveWorkout(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        // WorkoutSessions
                        ForEach(sessions(for: date)) { workout in
                            WorkoutSessionListRow(workout: workout) {
                                onWorkoutTap(workout)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(date, format: .dateTime.weekday(.wide).month().day())
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Workout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Live Workout List Row (for List context)

private struct LiveWorkoutListRow: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    private var exerciseCount: Int { workout.entries?.count ?? 0 }
    private var totalSets: Int { workout.entries?.reduce(0) { $0 + $1.sets.count } ?? 0 }
    private var durationMinutes: Int { Int(workout.duration / 60) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: workout.type == .cardio ? "figure.run" : "dumbbell.fill")
                    .font(.body)
                    .foregroundStyle(.accent)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        if exerciseCount > 0 { Text("\(exerciseCount) exercises") }
                        if totalSets > 0 {
                            Text("•").foregroundStyle(.tertiary)
                            Text("\(totalSets) sets")
                        }
                        if durationMinutes > 0 {
                            Text("•").foregroundStyle(.tertiary)
                            Text("\(durationMinutes) min")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Session List Row (for List context)

private struct WorkoutSessionListRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: workout.isStrengthTraining ? "dumbbell.fill" : "figure.run")
                    .font(.body)
                    .foregroundStyle(workout.sourceIsHealthKit ? .red : .accent)
                    .frame(width: 32, height: 32)
                    .background((workout.sourceIsHealthKit ? Color.red : Color.accentColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        if workout.isStrengthTraining {
                            Text("\(workout.sets)×\(workout.reps)")
                        } else {
                            if let duration = workout.formattedDuration { Text(duration) }
                            if let distance = workout.formattedDistance {
                                Text("•").foregroundStyle(.tertiary)
                                Text(distance)
                            }
                        }

                        if let calories = workout.caloriesBurned {
                            Text("•").foregroundStyle(.tertiary)
                            Text("\(calories) kcal")
                        }

                        if workout.sourceIsHealthKit {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
