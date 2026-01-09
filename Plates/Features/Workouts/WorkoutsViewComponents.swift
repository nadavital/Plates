//
//  WorkoutsViewComponents.swift
//  Plates
//
//  Supporting card components for WorkoutsView
//

import SwiftUI

// MARK: - Quick Start Card

struct QuickStartCard: View {
    let onStartBlankWorkout: () -> Void

    var body: some View {
        Button(action: onStartBlankWorkout) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Custom Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Add exercises as you go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active Workout Banner

struct ActiveWorkoutBanner: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Pulsing indicator
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.green.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in Progress")
                        .font(.subheadline)
                        .bold()
                    Text(workout.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(workout.formattedDuration)
                    .font(.headline)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.15))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.green.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Todays Workout Summary

struct TodaysWorkoutSummary: View {
    let workouts: [WorkoutSession]
    var liveWorkouts: [LiveWorkout] = []

    private var totalWorkoutCount: Int {
        workouts.count + liveWorkouts.count
    }

    private var totalDuration: Int {
        let sessionDuration = workouts.compactMap { $0.durationMinutes }.reduce(0) { $0 + Int($1) }
        let liveDuration = liveWorkouts.reduce(0) { $0 + Int($1.duration / 60) }
        return sessionDuration + liveDuration
    }

    private var totalCalories: Int {
        let sessionCalories = workouts.compactMap(\.caloriesBurned).reduce(0, +)
        let liveCalories = liveWorkouts.compactMap { $0.healthKitCalories.map { Int($0) } }.reduce(0, +)
        return sessionCalories + liveCalories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Activity", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
            }

            if totalWorkoutCount == 0 {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.secondary)
                    Text("No workouts yet today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 24) {
                    WorkoutStatItem(
                        value: "\(totalWorkoutCount)",
                        label: totalWorkoutCount == 1 ? "workout" : "workouts",
                        icon: "figure.run",
                        color: .orange
                    )

                    if totalDuration > 0 {
                        WorkoutStatItem(
                            value: "\(totalDuration)",
                            label: "minutes",
                            icon: "clock.fill",
                            color: .blue
                        )
                    }

                    if totalCalories > 0 {
                        WorkoutStatItem(
                            value: "\(totalCalories)",
                            label: "kcal",
                            icon: "flame.fill",
                            color: .red
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Stat Item

struct WorkoutStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout History Section

struct WorkoutHistorySection: View {
    let workoutsByDate: [(date: Date, workouts: [WorkoutSession])]
    let liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDelete: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    @State private var showAllWorkouts = false

    /// Merged and sorted list of all workout dates
    private var allDates: [Date] {
        let sessionDates = Set(workoutsByDate.map { $0.date })
        let liveDates = Set(liveWorkoutsByDate.map { $0.date })
        return sessionDates.union(liveDates).sorted(by: >)
    }

    /// Total workout count for "See All" button
    private var totalWorkoutCount: Int {
        let sessionCount = workoutsByDate.reduce(0) { $0 + $1.workouts.count }
        let liveCount = liveWorkoutsByDate.reduce(0) { $0 + $1.workouts.count }
        return sessionCount + liveCount
    }

    private func sessions(for date: Date) -> [WorkoutSession] {
        workoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    private func liveWorkouts(for date: Date) -> [LiveWorkout] {
        liveWorkoutsByDate.first { $0.date == date }?.workouts ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with See All button
            HStack {
                Label("Recent Workouts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.headline)
                Spacer()
                if totalWorkoutCount > 3 {
                    Button {
                        showAllWorkouts = true
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(.accent)
                    }
                }
            }

            if allDates.isEmpty {
                EmptyWorkoutHistory()
            } else {
                // Show only most recent 2 dates (compact view)
                VStack(spacing: 8) {
                    ForEach(allDates.prefix(2), id: \.self) { date in
                        CompactWorkoutDateGroup(
                            date: date,
                            sessions: sessions(for: date),
                            liveWorkouts: liveWorkouts(for: date),
                            onSessionTap: onWorkoutTap,
                            onLiveWorkoutTap: onLiveWorkoutTap
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .sheet(isPresented: $showAllWorkouts) {
            AllWorkoutsSheet(
                workoutsByDate: workoutsByDate,
                liveWorkoutsByDate: liveWorkoutsByDate,
                onWorkoutTap: onWorkoutTap,
                onLiveWorkoutTap: onLiveWorkoutTap,
                onDelete: onDelete,
                onDeleteLiveWorkout: onDeleteLiveWorkout
            )
        }
    }
}

// MARK: - Compact Workout Date Group (for preview)

private struct CompactWorkoutDateGroup: View {
    let date: Date
    let sessions: [WorkoutSession]
    let liveWorkouts: [LiveWorkout]
    let onSessionTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                // Show first 2 workouts from this date
                ForEach(liveWorkouts.prefix(2)) { workout in
                    CompactLiveWorkoutRow(workout: workout, onTap: { onLiveWorkoutTap(workout) })
                }

                ForEach(sessions.prefix(max(0, 2 - liveWorkouts.count))) { workout in
                    CompactWorkoutSessionRow(workout: workout, onTap: { onSessionTap(workout) })
                }
            }
        }
    }
}

// MARK: - Compact Live Workout Row

private struct CompactLiveWorkoutRow: View {
    let workout: LiveWorkout
    let onTap: () -> Void

    private var exerciseCount: Int { workout.entries?.count ?? 0 }
    private var totalSets: Int { workout.entries?.reduce(0) { $0 + $1.sets.count } ?? 0 }
    private var durationMinutes: Int { Int(workout.duration / 60) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
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
                        if exerciseCount > 0 {
                            Text("\(exerciseCount) exercises")
                        }
                        if totalSets > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(totalSets) sets")
                        }
                        if durationMinutes > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(durationMinutes) min")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Workout Session Row

private struct CompactWorkoutSessionRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
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
                        } else if let duration = workout.formattedDuration {
                            Text(duration)
                        }

                        if let calories = workout.caloriesBurned {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(calories) kcal")
                        }

                        if workout.sourceIsHealthKit {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

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

// MARK: - Combined Workout Date Group

struct CombinedWorkoutDateGroup: View {
    let date: Date
    let sessions: [WorkoutSession]
    let liveWorkouts: [LiveWorkout]
    let onSessionTap: (WorkoutSession) -> Void
    let onLiveWorkoutTap: (LiveWorkout) -> Void
    let onDeleteSession: (WorkoutSession) -> Void
    let onDeleteLiveWorkout: (LiveWorkout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                // Show in-app workouts first (LiveWorkout)
                ForEach(liveWorkouts) { workout in
                    LiveWorkoutHistoryRow(
                        workout: workout,
                        onTap: { onLiveWorkoutTap(workout) },
                        onDelete: { onDeleteLiveWorkout(workout) }
                    )
                }

                // Then show HealthKit/session workouts
                ForEach(sessions) { workout in
                    WorkoutHistoryRow(
                        workout: workout,
                        onTap: { onSessionTap(workout) },
                        onDelete: { onDeleteSession(workout) }
                    )
                }
            }
        }
    }
}

// MARK: - Live Workout History Row

struct LiveWorkoutHistoryRow: View {
    let workout: LiveWorkout
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    private var exerciseCount: Int {
        workout.entries?.count ?? 0
    }

    private var totalSets: Int {
        workout.entries?.reduce(0) { $0 + ($1.sets.count) } ?? 0
    }

    private var durationMinutes: Int {
        Int(workout.duration / 60)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
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
                        if exerciseCount > 0 {
                            Text("\(exerciseCount) exercises")
                        }
                        if totalSets > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(totalSets) sets")
                        }
                        if durationMinutes > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(durationMinutes) min")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(workout.name)\"? This cannot be undone.")
        }
    }
}

// MARK: - Workout Date Group

struct WorkoutDateGroup: View {
    let date: Date
    let workouts: [WorkoutSession]
    let onWorkoutTap: (WorkoutSession) -> Void
    let onDelete: (WorkoutSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(workouts) { workout in
                WorkoutHistoryRow(
                    workout: workout,
                    onTap: { onWorkoutTap(workout) },
                    onDelete: { onDelete(workout) }
                )
            }
        }
    }
}

// MARK: - Workout History Row

struct WorkoutHistoryRow: View {
    let workout: WorkoutSession
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with colored background
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
                            if let duration = workout.formattedDuration {
                                Text(duration)
                            }
                            if let distance = workout.formattedDistance {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(distance)
                            }
                        }

                        if let calories = workout.caloriesBurned {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(calories) kcal")
                        }

                        if workout.sourceIsHealthKit {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(workout.displayName)\"? This cannot be undone.")
        }
    }
}

// MARK: - Empty Workout History

struct EmptyWorkoutHistory: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No workouts yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Start your first workout to see it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Custom Workout Setup Sheet

struct CustomWorkoutSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (String, LiveWorkout.WorkoutType, [LiveWorkout.MuscleGroup]) -> Void

    @State private var workoutName = ""
    @State private var selectedType: LiveWorkout.WorkoutType = .strength
    @State private var selectedMuscles: Set<LiveWorkout.MuscleGroup> = []

    private var canStart: Bool {
        !workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMuscles.isEmpty
    }

    private var defaultName: String {
        if selectedMuscles.isEmpty {
            return "Custom Workout"
        }
        let muscleNames = selectedMuscles.sorted { $0.displayName < $1.displayName }
            .prefix(3)
            .map { $0.displayName }
            .joined(separator: " + ")
        return muscleNames
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Workout name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("e.g., Arm Day, Push Day", text: $workoutName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Workout type
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            WorkoutTypeButton(
                                type: .strength,
                                isSelected: selectedType == .strength
                            ) { selectedType = .strength }

                            WorkoutTypeButton(
                                type: .cardio,
                                isSelected: selectedType == .cardio
                            ) { selectedType = .cardio }

                            WorkoutTypeButton(
                                type: .mixed,
                                isSelected: selectedType == .mixed
                            ) { selectedType = .mixed }
                        }
                    }

                    // Muscle groups (for strength/mixed)
                    if selectedType != .cardio {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Target Muscle Groups")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Select what you want to train today")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            // Quick presets
                            HStack(spacing: 8) {
                                PresetButton(title: "Push", isSelected: isPushSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.pushMuscles)
                                }
                                PresetButton(title: "Pull", isSelected: isPullSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.pullMuscles)
                                }
                                PresetButton(title: "Legs", isSelected: isLegsSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.legMuscles)
                                }
                                PresetButton(title: "Full Body", isSelected: isFullBodySelected) {
                                    togglePreset([.fullBody])
                                }
                            }

                            // Individual muscle groups
                            FlowLayout(spacing: 8) {
                                ForEach(LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }) { muscle in
                                    WorkoutMuscleChip(
                                        muscle: muscle,
                                        isSelected: selectedMuscles.contains(muscle)
                                    ) {
                                        toggleMuscle(muscle)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let name = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = name.isEmpty ? defaultName : name
                        onStart(finalName, selectedType, Array(selectedMuscles))
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Presets

    private var isPushSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pushMuscles).isSubset(of: selectedMuscles)
    }

    private var isPullSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pullMuscles).isSubset(of: selectedMuscles)
    }

    private var isLegsSelected: Bool {
        Set(LiveWorkout.MuscleGroup.legMuscles).isSubset(of: selectedMuscles)
    }

    private var isFullBodySelected: Bool {
        selectedMuscles.contains(.fullBody)
    }

    private func togglePreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        let muscleSet = Set(muscles)
        if muscleSet.isSubset(of: selectedMuscles) {
            // Remove preset
            selectedMuscles.subtract(muscleSet)
        } else {
            // Add preset (and remove fullBody if adding specific muscles)
            selectedMuscles.formUnion(muscleSet)
            if muscles != [.fullBody] {
                selectedMuscles.remove(.fullBody)
            }
        }
        HapticManager.lightTap()
    }

    private func toggleMuscle(_ muscle: LiveWorkout.MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
            // Remove fullBody if adding specific muscles
            if muscle != .fullBody {
                selectedMuscles.remove(.fullBody)
            }
        }
        HapticManager.selectionChanged()
    }
}

// MARK: - Workout Type Button

private struct WorkoutTypeButton: View {
    let type: LiveWorkout.WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.title2)
                Text(type.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Muscle Chip

private struct WorkoutMuscleChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: muscle.iconName)
                    .font(.caption)
                Text(muscle.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ActiveWorkoutBanner(
                workout: {
                    let w = LiveWorkout(name: "Push Day", workoutType: .strength, targetMuscleGroups: [.chest, .shoulders, .triceps])
                    return w
                }(),
                onTap: {}
            )

            TodaysWorkoutSummary(workouts: [])
        }
        .padding()
    }
}
