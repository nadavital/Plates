//
//  LiveWorkoutViewModel.swift
//  Plates
//
//  Manages state for live workout tracking
//

import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable
final class LiveWorkoutViewModel {
    // MARK: - Properties

    var workout: LiveWorkout
    var isTimerRunning = true

    // Timer state - use date calculation for accuracy
    private(set) var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    /// Total pause duration including any active pause (for UI display)
    var totalPauseDuration: TimeInterval {
        let currentPause = pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
        return pausedDuration + currentPause
    }

    /// Calculated elapsed time (accurate, doesn't drift)
    var elapsedTime: TimeInterval {
        let totalElapsed = Date().timeIntervalSince(workout.startedAt)
        let currentPauseDuration = pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
        return totalElapsed - pausedDuration - currentPauseDuration
    }

    // Exercise suggestions from template (not pre-logged)
    var exerciseSuggestions: [ExerciseSuggestion] = []

    // Cache of last performances for exercises
    var lastPerformances: [String: ExerciseHistory] = [:]

    // User preferences cache (exercise usage frequency)
    var exerciseUsageFrequency: [String: Int] = [:]

    private var modelContext: ModelContext?
    private var templateService = WorkoutTemplateService()

    // MARK: - Exercise Suggestion Model

    struct ExerciseSuggestion: Identifiable, Equatable {
        let id = UUID()
        let exerciseName: String
        let muscleGroup: String
        let defaultSets: Int
        let defaultReps: Int
        var isAdded: Bool = false

        static func == (lhs: ExerciseSuggestion, rhs: ExerciseSuggestion) -> Bool {
            lhs.exerciseName == rhs.exerciseName
        }
    }

    // MARK: - Computed Properties

    var workoutName: String {
        workout.name.isEmpty ? "Workout" : workout.name
    }

    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var entries: [LiveWorkoutEntry] {
        (workout.entries ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    var totalSets: Int {
        entries.reduce(0) { $0 + $1.sets.count }
    }

    var completedSets: Int {
        entries.reduce(0) { $0 + ($1.completedSets?.count ?? 0) }
    }

    var totalVolume: Double {
        entries.reduce(0) { $0 + $1.totalVolume }
    }

    var isWorkoutComplete: Bool {
        !entries.isEmpty && entries.allSatisfy { entry in
            entry.sets.allSatisfy(\.completed)
        }
    }

    /// Target muscle groups for this workout
    var targetMuscleGroups: [String] {
        workout.muscleGroups.map(\.rawValue)
    }

    /// Suggestions that haven't been added yet
    var availableSuggestions: [ExerciseSuggestion] {
        exerciseSuggestions.filter { !$0.isAdded }
    }

    /// Smart "Up Next" suggestion - rotates through muscle groups, prioritizes user's exercises
    var upNextSuggestion: ExerciseSuggestion? {
        let available = availableSuggestions
        guard !available.isEmpty else { return nil }

        // Split into exercises user has used before vs never used
        let usedExercises = available.filter { exerciseUsageFrequency[$0.exerciseName, default: 0] > 0 }
        let unusedExercises = available.filter { exerciseUsageFrequency[$0.exerciseName, default: 0] == 0 }

        // Prefer exercises user has actually used before
        let preferredPool = usedExercises.isEmpty ? available : usedExercises

        // Find last muscle group worked - prefer different muscle group for rotation
        if let lastEntry = entries.last,
           let lastSuggestion = exerciseSuggestions.first(where: { $0.exerciseName == lastEntry.exerciseName }) {
            let lastMuscle = lastSuggestion.muscleGroup

            // Prefer a different muscle group than the last one (from preferred pool first)
            if let differentMuscle = preferredPool.first(where: { $0.muscleGroup != lastMuscle }) {
                return differentMuscle
            }
            // Fall back to unused exercises with different muscle
            if let differentMuscle = unusedExercises.first(where: { $0.muscleGroup != lastMuscle }) {
                return differentMuscle
            }
        }

        // Sort by user preference (most used first)
        let sortedByPreference = preferredPool.sorted { a, b in
            (exerciseUsageFrequency[a.exerciseName] ?? 0) > (exerciseUsageFrequency[b.exerciseName] ?? 0)
        }

        return sortedByPreference.first ?? unusedExercises.first
    }

    /// Group available suggestions by muscle group
    var suggestionsByMuscle: [String: [ExerciseSuggestion]] {
        Dictionary(grouping: availableSuggestions) { $0.muscleGroup }
    }

    // MARK: - Initialization

    init(workout: LiveWorkout, suggestions: [ExerciseSuggestion] = []) {
        self.workout = workout
        // elapsedTime is now computed from workout.startedAt
        self.exerciseSuggestions = suggestions
    }

    /// Initialize with an existing workout and optional template for suggestions
    convenience init(workout: LiveWorkout, template: WorkoutPlan.WorkoutTemplate?) {
        // Create suggestions from template exercises if provided
        let suggestions: [ExerciseSuggestion]
        if let template {
            suggestions = template.exercises.sorted(by: { $0.order < $1.order }).map { exercise in
                ExerciseSuggestion(
                    exerciseName: exercise.exerciseName,
                    muscleGroup: exercise.muscleGroup,
                    defaultSets: exercise.defaultSets,
                    defaultReps: exercise.defaultReps
                )
            }
        } else {
            suggestions = []
        }

        self.init(workout: workout, suggestions: suggestions)
    }

    // MARK: - Setup

    func setup(with modelContext: ModelContext) {
        self.modelContext = modelContext

        // Insert workout if not already persisted
        if workout.modelContext == nil {
            modelContext.insert(workout)
            try? modelContext.save()
        }

        startTimer()
        loadLastPerformances()
        loadExerciseUsageFrequency()
        loadSuggestionPerformances()
    }

    /// Load exercise usage frequency from history
    private func loadExerciseUsageFrequency() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<ExerciseHistory>()
        guard let history = try? modelContext.fetch(descriptor) else { return }

        // Count occurrences of each exercise
        var frequency: [String: Int] = [:]
        for record in history {
            frequency[record.exerciseName, default: 0] += 1
        }
        exerciseUsageFrequency = frequency
    }

    /// Load last performances for suggested exercises
    private func loadSuggestionPerformances() {
        guard let modelContext else { return }

        for suggestion in exerciseSuggestions {
            if let lastPerformance = templateService.getLastPerformance(
                exerciseName: suggestion.exerciseName,
                modelContext: modelContext
            ) {
                lastPerformances[suggestion.exerciseName] = lastPerformance
            }
        }
    }

    // MARK: - Last Performance

    /// Load last performances for all exercises in the workout
    func loadLastPerformances() {
        guard let modelContext else { return }

        for entry in entries {
            if let lastPerformance = templateService.getLastPerformance(
                exerciseName: entry.exerciseName,
                modelContext: modelContext
            ) {
                lastPerformances[entry.exerciseName] = lastPerformance
            }
        }
    }

    /// Get last performance for a specific exercise
    func getLastPerformance(for exerciseName: String) -> ExerciseHistory? {
        // Check cache first
        if let cached = lastPerformances[exerciseName] {
            return cached
        }

        // Fetch if not cached
        guard let modelContext else { return nil }
        let performance = templateService.getLastPerformance(
            exerciseName: exerciseName,
            modelContext: modelContext
        )
        if let performance {
            lastPerformances[exerciseName] = performance
        }
        return performance
    }

    // MARK: - Timer
    // Note: Timer display is handled by TimelineView in the UI for better scroll performance.
    // This view model just tracks pause state and provides elapsedTime calculation.

    func startTimer() {
        // No-op - TimelineView handles UI refresh
        // Keeping method for API compatibility
        isTimerRunning = true
    }

    func pauseTimer() {
        isTimerRunning = false
        pauseStartTime = Date()  // Record when pause started
    }

    func resumeTimer() {
        // Add pause duration and clear pause start
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        isTimerRunning = true
    }

    func stopTimer() {
        // Finalize any active pause
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        isTimerRunning = false
    }

    // MARK: - Suggestion Management

    /// Add an exercise from a suggestion - marks suggestion as added and creates entry
    func addExerciseFromSuggestion(_ suggestion: ExerciseSuggestion) {
        // Mark suggestion as added
        if let index = exerciseSuggestions.firstIndex(where: { $0.exerciseName == suggestion.exerciseName }) {
            exerciseSuggestions[index].isAdded = true
        }

        let entry = LiveWorkoutEntry(exerciseName: suggestion.exerciseName, orderIndex: entries.count)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: suggestion.exerciseName)

        // Use first value from user's rep/weight pattern, or fall back to defaults
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? suggestion.defaultReps
        let suggestedWeight = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weightKg: suggestedWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        save()
    }

    /// Add the "Up Next" suggested exercise
    func addUpNextExercise() {
        guard let suggestion = upNextSuggestion else { return }
        addExerciseFromSuggestion(suggestion)
    }

    // MARK: - Exercise Management

    func addExercise(_ exercise: Exercise) {
        let entry = LiveWorkoutEntry(exercise: exercise, orderIndex: entries.count)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: exercise.name)

        // Use first value from user's rep/weight pattern
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? 10
        let suggestedWeight = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weightKg: suggestedWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        save()
    }

    func addExerciseByName(_ name: String, exerciseType: String = "strength") {
        let entry = LiveWorkoutEntry(exerciseName: name, orderIndex: entries.count, exerciseType: exerciseType)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: name)

        // Use first value from user's rep/weight pattern
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? 10
        let suggestedWeight = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weightKg: suggestedWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        save()
    }

    func removeExercise(at index: Int) {
        guard index < entries.count else { return }
        let entry = entries[index]
        workout.entries?.removeAll { $0.id == entry.id }

        // Reorder remaining entries
        for (newIndex, entry) in (workout.entries ?? []).enumerated() {
            entry.orderIndex = newIndex
        }

        save()
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        var mutableEntries = entries
        mutableEntries.move(fromOffsets: source, toOffset: destination)

        for (index, entry) in mutableEntries.enumerated() {
            entry.orderIndex = index
        }

        save()
    }

    // MARK: - Set Management

    func addSet(to entry: LiveWorkoutEntry) {
        let currentSetIndex = entry.sets.count
        let lastSet = entry.sets.last

        // Check if we have a pattern from last performance
        let lastPerformance = getLastPerformance(for: entry.exerciseName)
        let repPattern = lastPerformance?.repPatternArray ?? []
        let weightPattern = lastPerformance?.weightPatternArray ?? []

        // Suggest next reps/weight based on pattern, or copy last set
        let suggestedReps: Int
        let suggestedWeight: Double

        if currentSetIndex < repPattern.count {
            // Use the next value from user's historical pattern
            suggestedReps = repPattern[currentSetIndex]
            suggestedWeight = currentSetIndex < weightPattern.count ? weightPattern[currentSetIndex] : (lastSet?.weightKg ?? 0)
        } else {
            // No pattern or past pattern length - copy last set
            suggestedReps = lastSet?.reps ?? 10
            suggestedWeight = lastSet?.weightKg ?? 0
        }

        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weightKg: suggestedWeight,
            completed: false,
            isWarmup: false
        ))
        save()
    }

    func updateSet(at index: Int, in entry: LiveWorkoutEntry, reps: Int? = nil, weight: Double? = nil, notes: String? = nil) {
        let sets = entry.sets
        guard index < sets.count else { return }

        var set = sets[index]
        if let reps {
            set.reps = reps
        }
        if let weight {
            set.weightKg = weight
        }
        if let notes {
            set.notes = notes
        }
        entry.updateSet(at: index, with: set)
        save()
    }

    func removeSet(at index: Int, from entry: LiveWorkoutEntry) {
        entry.removeSet(at: index)
        save()
    }

    func toggleWarmup(at index: Int, in entry: LiveWorkoutEntry) {
        let sets = entry.sets
        guard index < sets.count else { return }

        var set = sets[index]
        set.isWarmup.toggle()
        entry.updateSet(at: index, with: set)
        save()
    }

    // MARK: - Cardio Management

    func updateCardioDuration(for entry: LiveWorkoutEntry, seconds: Int) {
        entry.durationSeconds = seconds
        save()
    }

    func updateCardioDistance(for entry: LiveWorkoutEntry, meters: Double) {
        entry.distanceMeters = meters
        save()
    }

    func toggleCardioCompletion(for entry: LiveWorkoutEntry) {
        if entry.completedAt != nil {
            entry.completedAt = nil
        } else {
            entry.completedAt = Date()
        }
        save()
        HapticManager.selectionChanged()
    }

    // MARK: - Muscle Groups

    func updateMuscleGroups(_ muscles: [LiveWorkout.MuscleGroup]) {
        workout.muscleGroups = muscles
        // Update workout name based on muscles if it's still the default
        if workout.name == "Custom Workout" && !muscles.isEmpty {
            let muscleNames = muscles.sorted { $0.displayName < $1.displayName }
                .prefix(3)
                .map { $0.displayName }
                .joined(separator: " + ")
            workout.name = muscleNames
        }
        save()
    }

    // MARK: - Workout Completion

    func finishWorkout() {
        stopTimer()
        workout.completedAt = Date()

        // Create ExerciseHistory entries for each exercise
        createExerciseHistoryEntries()

        // Try to merge with overlapping Apple Watch workout
        Task {
            await mergeWithAppleWatchWorkout()
        }

        save()
    }

    /// Check for overlapping Apple Watch workout and merge data
    private func mergeWithAppleWatchWorkout() async {
        let healthKitService = HealthKitService()

        do {
            try await healthKitService.requestAuthorization()

            // Search in a wider window to catch workouts that started before/after ours
            let searchStart = workout.startedAt.addingTimeInterval(-15 * 60) // 15 min before
            let searchEnd = (workout.completedAt ?? Date()).addingTimeInterval(15 * 60) // 15 min after

            let healthKitWorkouts = try await healthKitService.fetchWorkouts(
                from: searchStart,
                to: searchEnd
            )

            // Find best overlapping workout (prefer strength training types)
            let overlapping = findBestOverlappingWorkout(from: healthKitWorkouts)

            guard let match = overlapping else { return }

            // Merge data from Apple Watch
            workout.mergedHealthKitWorkoutID = match.healthKitWorkoutID
            if let calories = match.caloriesBurned {
                workout.healthKitCalories = Double(calories)
            }
            if let avgHR = match.averageHeartRate {
                workout.healthKitAvgHeartRate = Double(avgHR)
            }

            save()
        } catch {
            // Silently fail - HealthKit merge is optional
            print("HealthKit merge failed: \(error)")
        }
    }

    /// Find the best overlapping workout from HealthKit results
    private func findBestOverlappingWorkout(from healthKitWorkouts: [WorkoutSession]) -> WorkoutSession? {
        let ourStart = workout.startedAt
        let ourEnd = workout.completedAt ?? Date()

        // Filter to only overlapping workouts
        let overlapping = healthKitWorkouts.filter { hkWorkout in
            let hkStart = hkWorkout.loggedAt
            let hkEnd = calculateEndDate(for: hkWorkout) ?? hkStart

            // Check for any overlap
            return hkStart <= ourEnd && hkEnd >= ourStart
        }

        // Prefer strength training workouts ("Traditional Strength Training", "Functional Strength Training")
        let strengthWorkouts = overlapping.filter {
            $0.healthKitWorkoutType?.lowercased().contains("strength") == true ||
            $0.healthKitWorkoutType?.lowercased().contains("weight") == true
        }

        // Return best match: strength workout if available, otherwise first overlapping
        return strengthWorkouts.first ?? overlapping.first
    }

    private func calculateEndDate(for workout: WorkoutSession) -> Date? {
        guard let duration = workout.durationMinutes, duration > 0 else {
            // If no duration, assume a reasonable default (e.g., 1 hour)
            return workout.loggedAt.addingTimeInterval(60 * 60)
        }
        return workout.loggedAt.addingTimeInterval(duration * 60)
    }

    func cancelWorkout() {
        stopTimer()
        modelContext?.delete(workout)
        try? modelContext?.save()
    }

    // MARK: - Private Methods

    private func createExerciseHistoryEntries() {
        for entry in entries {
            guard entry.completedSets?.isEmpty == false else { continue }

            let history = ExerciseHistory(from: entry, performedAt: workout.completedAt ?? Date())
            modelContext?.insert(history)
        }
    }

    private func save() {
        try? modelContext?.save()
    }
}
