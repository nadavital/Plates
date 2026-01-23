//
//  LiveWorkoutViewModel.swift
//  Trai
//
//  Manages state for live workout tracking
//

import ActivityKit
import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable
final class LiveWorkoutViewModel {
    // MARK: - Properties

    var workout: LiveWorkout
    var isTimerRunning = true

    // Live Activity manager (shared singleton to prevent duplicates)
    private var liveActivityManager: LiveActivityManager { LiveActivityManager.shared }
    private var liveActivityUpdateTimer: Timer?

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

    // Cache of personal records (all-time max weight) for exercises
    var personalRecords: [String: ExerciseHistory] = [:]

    // PRs achieved during this workout (exercise name -> PR details)
    var achievedPRs: [String: PRValue] = [:]

    enum PRType: String {
        case weight = "Weight PR"
        case volume = "Volume PR"
        case reps = "Rep PR"
    }

    struct PRValue: Equatable {
        let type: PRType
        let exerciseName: String
        let newValue: Double
        let previousValue: Double
        let isFirstTime: Bool

        var improvement: Double { newValue - previousValue }

        var formattedNewValue: String {
            switch type {
            case .weight: return String(format: "%.1f kg", newValue)
            case .volume: return String(format: "%.0f kg", newValue)
            case .reps: return "\(Int(newValue)) reps"
            }
        }

        var formattedImprovement: String {
            guard !isFirstTime && improvement > 0 else { return "" }
            switch type {
            case .weight: return String(format: "+%.1f kg", improvement)
            case .volume: return String(format: "+%.0f kg", improvement)
            case .reps: return "+\(Int(improvement)) reps"
            }
        }
    }

    // User preferences cache (exercise usage frequency)
    var exerciseUsageFrequency: [String: Int] = [:]

    // Apple Watch data (via HealthKit)
    var currentHeartRate: Double?
    var lastHeartRateUpdate: Date?
    var workoutCalories: Double = 0
    var lastCalorieUpdate: Date?
    var isHeartRateAvailable: Bool { currentHeartRate != nil }
    var isWatchConnected: Bool { healthKitService?.isWatchConnected ?? false }

    private var modelContext: ModelContext?
    private var templateService = WorkoutTemplateService()
    private var healthKitService: HealthKitService?

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

    /// Count of sets with data entered (reps > 0) - shows workout progress during active workout
    var completedSets: Int {
        entries.reduce(0) { total, entry in
            total + entry.sets.filter { !$0.isWarmup && $0.reps > 0 }.count
        }
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
    /// Filters out exercises already in the current workout
    var upNextSuggestion: ExerciseSuggestion? {
        let available = availableSuggestions
        guard !available.isEmpty else { return nil }

        // Get all exercise names currently in this workout
        let currentExerciseNames = Set(entries.map { $0.exerciseName })

        // Filter out exercises already in the workout
        let notInWorkout = available.filter { !currentExerciseNames.contains($0.exerciseName) }
        guard !notInWorkout.isEmpty else { return nil }

        // Split into exercises user has used before vs never used
        let usedExercises = notInWorkout.filter { exerciseUsageFrequency[$0.exerciseName, default: 0] > 0 }
        let unusedExercises = notInWorkout.filter { exerciseUsageFrequency[$0.exerciseName, default: 0] == 0 }

        // Prefer exercises user has actually used before
        let preferredPool = usedExercises.isEmpty ? notInWorkout : usedExercises

        // Get last 2 muscle groups worked - avoid immediate repeats
        let recentMuscleGroups: Set<String> = {
            var muscles = Set<String>()
            let recentEntries = entries.suffix(2)
            for entry in recentEntries {
                if let muscle = getMuscleGroup(for: entry) {
                    muscles.insert(muscle)
                }
            }
            return muscles
        }()

        if !recentMuscleGroups.isEmpty {
            // Filter out exercises from the same muscle groups as the last 2 exercises
            let differentMusclePool = preferredPool.filter { !recentMuscleGroups.contains($0.muscleGroup) }
            let differentMuscleUnused = unusedExercises.filter { !recentMuscleGroups.contains($0.muscleGroup) }

            // Prefer exercises from a different muscle group (from preferred pool first)
            if let suggestion = differentMusclePool.first {
                return suggestion
            }
            // Fall back to unused exercises with different muscle
            if let suggestion = differentMuscleUnused.first {
                return suggestion
            }
            // If no different muscle available, fall through to any available
        }

        // Sort by user preference (most used first)
        let sortedByPreference = preferredPool.sorted { a, b in
            (exerciseUsageFrequency[a.exerciseName] ?? 0) > (exerciseUsageFrequency[b.exerciseName] ?? 0)
        }

        return sortedByPreference.first ?? unusedExercises.first
    }

    /// Get the muscle group for a workout entry (checks suggestions first, then database)
    private func getMuscleGroup(for entry: LiveWorkoutEntry) -> String? {
        // First check if it's from our suggestions
        if let suggestion = exerciseSuggestions.first(where: { $0.exerciseName == entry.exerciseName }) {
            return suggestion.muscleGroup
        }

        // Look up the exercise in the database by name
        guard let modelContext else { return nil }
        let exerciseName = entry.exerciseName
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == exerciseName }
        )
        descriptor.fetchLimit = 1
        if let exercise = try? modelContext.fetch(descriptor).first {
            return exercise.muscleGroup
        }

        return nil
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

    func setup(with modelContext: ModelContext, healthKitService: HealthKitService? = nil) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService

        // Insert workout if not already persisted
        if workout.modelContext == nil {
            modelContext.insert(workout)
            try? modelContext.save()
        }

        startTimer()
        loadLastPerformances()
        loadExerciseUsageFrequency()

        // If no template suggestions, generate from target muscle groups
        if exerciseSuggestions.isEmpty {
            loadSuggestionsFromTargetMuscles()
        }

        loadSuggestionPerformances()

        // Start heart rate streaming from Apple Watch
        startHeartRateMonitoring()

        // Start Live Activity
        startLiveActivity()
    }

    // MARK: - Apple Watch Monitoring

    func startHeartRateMonitoring() {
        healthKitService?.startHeartRateStreaming()
        healthKitService?.startCalorieStreaming(from: workout.startedAt)
        updateWatchDataFromService()
    }

    func stopHeartRateMonitoring() {
        healthKitService?.stopHeartRateStreaming()
        healthKitService?.stopCalorieStreaming()
        currentHeartRate = nil
        lastHeartRateUpdate = nil
    }

    /// Updates heart rate and calories from the HealthKit service - called by the view
    func updateWatchDataFromService() {
        guard let service = healthKitService else { return }
        currentHeartRate = service.currentHeartRate
        lastHeartRateUpdate = service.lastHeartRateUpdate
        workoutCalories = service.workoutCalories
        lastCalorieUpdate = service.lastCalorieUpdate
    }

    /// Legacy method for backwards compatibility
    func updateHeartRateFromService() {
        updateWatchDataFromService()
    }

    /// Load exercise suggestions based on workout's target muscle groups
    private func loadSuggestionsFromTargetMuscles() {
        guard let modelContext,
              !workout.targetMuscleGroups.isEmpty else { return }

        // Parse target muscle groups from comma-separated string
        let targetMuscles = workout.targetMuscleGroups
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !targetMuscles.isEmpty else { return }

        // Map LiveWorkout.MuscleGroup to Exercise.MuscleGroup strings
        let exerciseMuscleGroups = targetMuscles.flatMap { muscle -> [String] in
            switch muscle {
            case "chest", "back", "shoulders", "biceps", "triceps", "core":
                return [muscle]
            case "quads", "hamstrings", "glutes", "calves":
                return ["legs"]  // Exercise model uses "legs" for all leg muscles
            case "fullBody":
                return ["chest", "back", "shoulders", "biceps", "triceps", "core", "legs"]
            default:
                return [muscle]
            }
        }

        // Fetch exercises for target muscle groups
        let descriptor = FetchDescriptor<Exercise>()
        guard let exercises = try? modelContext.fetch(descriptor) else { return }

        let uniqueMuscles = Set(exerciseMuscleGroups)
        let matchingExercises = exercises.filter { exercise in
            guard let muscleGroup = exercise.muscleGroup else { return false }
            return uniqueMuscles.contains(muscleGroup)
        }

        // Sort by frequency (user's preferred exercises first)
        let sortedExercises = matchingExercises.sorted { a, b in
            (exerciseUsageFrequency[a.name] ?? 0) > (exerciseUsageFrequency[b.name] ?? 0)
        }

        // Create suggestions (limit to reasonable number)
        exerciseSuggestions = sortedExercises.prefix(12).map { exercise in
            ExerciseSuggestion(
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup ?? "other",
                defaultSets: 3,
                defaultReps: 10
            )
        }
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

    // MARK: - Last Performance & Personal Records

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
            // Also load PR
            if let pr = templateService.getPersonalRecord(
                exerciseName: entry.exerciseName,
                modelContext: modelContext
            ) {
                personalRecords[entry.exerciseName] = pr
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

    /// Get personal record (all-time max weight) for a specific exercise
    func getPersonalRecord(for exerciseName: String) -> ExerciseHistory? {
        // Check cache first
        if let cached = personalRecords[exerciseName] {
            return cached
        }

        // Fetch if not cached
        guard let modelContext else { return nil }
        let pr = templateService.getPersonalRecord(
            exerciseName: exerciseName,
            modelContext: modelContext
        )
        if let pr {
            personalRecords[exerciseName] = pr
        }
        return pr
    }

    /// Check if current workout entry exceeds the cached PR (live checking while editing)
    func isNewPR(for entry: LiveWorkoutEntry) -> PRType? {
        guard let cachedPR = personalRecords[entry.exerciseName] else {
            // First time doing this exercise - consider it a PR if there's weight
            let bestSet = entry.sets.filter { !$0.isWarmup && $0.reps > 0 }.max { $0.volume < $1.volume }
            if let best = bestSet, best.weightKg > 0 {
                return .weight
            }
            return nil
        }

        // Get best set from current entry
        let completedSets = entry.sets.filter { !$0.isWarmup && $0.reps > 0 }
        guard !completedSets.isEmpty else { return nil }

        let currentBestWeight = completedSets.map(\.weightKg).max() ?? 0
        let currentTotalVolume = completedSets.reduce(0) { $0 + $1.volume }
        let currentBestReps = completedSets.map(\.reps).max() ?? 0

        // Check for weight PR
        if currentBestWeight > cachedPR.bestSetWeightKg {
            return .weight
        }
        // Check for volume PR
        if currentTotalVolume > cachedPR.totalVolume {
            return .volume
        }
        // Check for rep PR (at same or higher weight)
        if currentBestReps > cachedPR.bestSetReps && currentBestWeight >= cachedPR.bestSetWeightKg {
            return .reps
        }

        return nil
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
        updateLiveActivity()
    }

    func resumeTimer() {
        // Add pause duration and clear pause start
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        isTimerRunning = true
        updateLiveActivity()
    }

    func stopTimer() {
        // Finalize any active pause
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        isTimerRunning = false
        stopHeartRateMonitoring()
        stopLiveActivityUpdates()
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

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
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

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
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

    /// Replace an existing exercise with a new one, keeping the same position
    func replaceExercise(_ existingEntry: LiveWorkoutEntry, with newExercise: Exercise) {
        let orderIndex = existingEntry.orderIndex

        // Create new entry with the same order index
        let newEntry = LiveWorkoutEntry(exercise: newExercise, orderIndex: orderIndex)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: newExercise.name)
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
        let suggestedWeight = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0

        // Start with 1 set
        newEntry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weightKg: suggestedWeight,
            completed: false,
            isWarmup: false
        ))

        // Remove old entry and add new one
        workout.entries?.removeAll { $0.id == existingEntry.id }
        newEntry.workout = workout
        modelContext?.insert(newEntry)
        workout.entries?.append(newEntry)

        // Re-sort entries by order index
        workout.entries?.sort { $0.orderIndex < $1.orderIndex }

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

        // For weight: prioritize current workout's last set if user modified it
        // This ensures that if user changes weight mid-workout, subsequent sets follow that weight
        if let lastSet, currentSetIndex > 0 {
            // Check if user changed weight from what the pattern suggested
            let patternWeight = currentSetIndex <= weightPattern.count ? weightPattern[currentSetIndex - 1] : 0
            let userModifiedWeight = abs(lastSet.weightKg - patternWeight) > 0.1

            if userModifiedWeight {
                // User overrode the pattern, follow their lead
                suggestedWeight = lastSet.weightKg
            } else if currentSetIndex < weightPattern.count {
                // Use pattern weight for this set
                suggestedWeight = weightPattern[currentSetIndex]
            } else {
                // Past pattern length, copy last set
                suggestedWeight = lastSet.weightKg
            }
        } else if currentSetIndex < weightPattern.count {
            suggestedWeight = weightPattern[currentSetIndex]
        } else {
            suggestedWeight = lastSet?.weightKg ?? 0
        }

        // For reps: use pattern or copy last set
        if currentSetIndex < repPattern.count {
            suggestedReps = repPattern[currentSetIndex]
        } else {
            suggestedReps = lastSet?.reps ?? getUserDefaultRepCount()
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

        // Auto-mark all sets with data as completed
        // (since set checking was removed from UI, we infer completion from having data)
        for entry in entries {
            for index in entry.sets.indices {
                let set = entry.sets[index]
                // Mark as completed if it has reps (user entered data)
                if set.reps > 0 && !set.completed {
                    var updatedSet = set
                    updatedSet.completed = true
                    entry.updateSet(at: index, with: updatedSet)
                }
            }
        }

        // Create ExerciseHistory entries for each exercise
        createExerciseHistoryEntries()

        // Try to merge with overlapping Apple Watch workout
        Task {
            await mergeWithAppleWatchWorkout()
        }

        // Note: Workout saving to HealthKit removed - Apple Watch automatically saves workouts

        // End Live Activity with summary
        liveActivityManager.endActivity(showSummary: true)

        // Notify dashboard to refresh muscle recovery
        NotificationCenter.default.post(
            name: .workoutCompleted,
            object: nil,
            userInfo: ["workoutId": workout.id]
        )

        save()
    }

    /// Get user's preferred default rep count from their profile
    private func getUserDefaultRepCount() -> Int {
        guard let modelContext else { return 10 }
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            return profile.defaultRepCount
        }
        return 10 // Fallback default
    }

    func cancelWorkout() {
        stopTimer()
        // End Live Activity immediately (no summary)
        liveActivityManager.endActivity(showSummary: false)
        modelContext?.delete(workout)
        try? modelContext?.save()
    }

    // MARK: - Private Methods

    private func createExerciseHistoryEntries() {
        for entry in entries {
            guard entry.completedSets?.isEmpty == false else { continue }

            let history = ExerciseHistory(from: entry, performedAt: workout.completedAt ?? Date())
            modelContext?.insert(history)

            // Check for PRs
            if let previousPR = personalRecords[entry.exerciseName] {
                // Weight PR
                if history.bestSetWeightKg > previousPR.bestSetWeightKg {
                    achievedPRs[entry.exerciseName] = PRValue(
                        type: .weight,
                        exerciseName: entry.exerciseName,
                        newValue: history.bestSetWeightKg,
                        previousValue: previousPR.bestSetWeightKg,
                        isFirstTime: false
                    )
                }
                // Volume PR (only if no weight PR already detected)
                else if history.totalVolume > previousPR.totalVolume,
                        achievedPRs[entry.exerciseName] == nil {
                    achievedPRs[entry.exerciseName] = PRValue(
                        type: .volume,
                        exerciseName: entry.exerciseName,
                        newValue: history.totalVolume,
                        previousValue: previousPR.totalVolume,
                        isFirstTime: false
                    )
                }
                // Rep PR (only if nothing else detected)
                else if history.bestSetReps > previousPR.bestSetReps,
                        achievedPRs[entry.exerciseName] == nil {
                    achievedPRs[entry.exerciseName] = PRValue(
                        type: .reps,
                        exerciseName: entry.exerciseName,
                        newValue: Double(history.bestSetReps),
                        previousValue: Double(previousPR.bestSetReps),
                        isFirstTime: false
                    )
                }
            } else if history.bestSetWeightKg > 0 {
                // First time doing this exercise - it's a PR by default
                achievedPRs[entry.exerciseName] = PRValue(
                    type: .weight,
                    exerciseName: entry.exerciseName,
                    newValue: history.bestSetWeightKg,
                    previousValue: 0,
                    isFirstTime: true
                )
            }
        }
    }

    func save() {
        try? modelContext?.save()
        // Update Live Activity when data changes
        updateLiveActivity()
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        liveActivityManager.startActivity(
            workoutName: workoutName,
            targetMuscles: targetMuscleGroups,
            startedAt: workout.startedAt
        )

        // Start periodic updates for elapsed time
        startLiveActivityUpdates()
    }

    private func startLiveActivityUpdates() {
        // Update every 5 seconds to avoid constant re-renders (improves typing performance)
        // The Live Activity timer display is not critical for real-time accuracy
        liveActivityUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLiveActivity()
            }
        }
    }

    private func stopLiveActivityUpdates() {
        liveActivityUpdateTimer?.invalidate()
        liveActivityUpdateTimer = nil
    }

    private func updateLiveActivity() {
        // Get current exercise (first incomplete or last one)
        let currentEntry = entries.first { entry in
            entry.sets.isEmpty || entry.sets.contains { !$0.completed }
        } ?? entries.last

        let currentExercise = currentEntry?.exerciseName

        // Get current set data (last set with data from current entry)
        let currentSet = currentEntry?.sets.last { $0.reps > 0 }
        let currentWeight = currentSet?.weightKg
        let currentReps = currentSet?.reps

        // Find next exercise (first after current that isn't started yet)
        let currentIndex = entries.firstIndex { $0.id == currentEntry?.id } ?? -1
        let nextExercise = entries.dropFirst(currentIndex + 1).first?.exerciseName

        liveActivityManager.updateActivity(
            elapsedSeconds: Int(elapsedTime),
            currentExercise: currentExercise,
            completedSets: completedSets,
            totalSets: totalSets,
            heartRate: currentHeartRate.map { Int($0) },
            isPaused: !isTimerRunning,
            currentWeight: currentWeight,
            currentReps: currentReps,
            totalVolumeKg: totalVolume,
            nextExercise: nextExercise
        )
    }
}
