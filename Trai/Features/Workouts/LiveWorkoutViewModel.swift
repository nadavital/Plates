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
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingLiveActivityUpdateTask: Task<Void, Never>?
    private let saveDebounceDelay: Duration = .milliseconds(500)
    private let liveActivityDebounceDelay: Duration = .milliseconds(300)
    
    // Live Activity intent handling via App Groups
    private var liveActivityIntentTimer: Timer?
    private var lastAddSetTimestamp: TimeInterval = 0
    private var lastTogglePauseTimestamp: TimeInterval = 0

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

    // Exercise suggestions generated from target muscles and user history
    var exerciseSuggestions: [ExerciseSuggestion] = []

    // Cache of last performances for exercises
    var lastPerformances: [String: ExerciseHistory] = [:]

    // Cache of personal records (all-time max weight) for exercises
    var personalRecords: [String: ExerciseHistory] = [:]
    var performanceSnapshots: [String: ExercisePerformanceSnapshot] = [:]

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

    private struct WorkoutMetrics {
        var totalSets: Int
        var completedSets: Int
        var totalVolume: Double

        static let zero = WorkoutMetrics(totalSets: 0, completedSets: 0, totalVolume: 0)
    }

    private var cachedEntries: [LiveWorkoutEntry] = []
    private var cachedMetrics: WorkoutMetrics = .zero
    private var cachedMuscleGroupByExerciseName: [String: String] = [:]

    // User preferences cache (exercise usage frequency)
    var exerciseUsageFrequency: [String: Int] = [:]

    // Apple Watch data (via HealthKit)
    var currentHeartRate: Double?
    var lastHeartRateUpdate: Date?
    var workoutCalories: Double = 0
    var lastCalorieUpdate: Date?
    var isHeartRateAvailable: Bool { currentHeartRate != nil }
    var isWatchConnected: Bool { healthKitService?.isWatchConnected ?? false }
    var watchSetupErrorMessage: String?
    var isRetryingWatchSync = false

    var watchConnectionHint: String? {
        if let watchSetupErrorMessage {
            return watchSetupErrorMessage
        }
        if isWatchConnected {
            return nil
        }
        if let lastHeartRateUpdate {
            let ageSeconds = Int(Date().timeIntervalSince(lastHeartRateUpdate))
            if ageSeconds >= 0 && ageSeconds <= 180 {
                return "Latest Apple Watch sample was \(ageSeconds)s ago. Keep the Watch workout running."
            }
        }
        return "Start or continue a workout on Apple Watch to stream live heart rate."
    }

    private var modelContext: ModelContext?
    private var performanceService = ExercisePerformanceService()
    private(set) var healthKitService: HealthKitService?
    private var usesMetricWeightPreference = true
    private let maxSuggestionPoolSize = 12

    // MARK: - Exercise Suggestion Model

    struct ExerciseSuggestion: Identifiable, Equatable {
        let id = UUID()
        let exerciseName: String
        let muscleGroup: String
        let defaultSets: Int
        let defaultReps: Int

        static func == (lhs: ExerciseSuggestion, rhs: ExerciseSuggestion) -> Bool {
            lhs.exerciseName == rhs.exerciseName
        }
    }

    enum SuggestionRebuildReason: String {
        case workoutStart
        case targetMusclesChanged
        case userRefresh
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
        cachedEntries
    }

    var totalSets: Int {
        cachedMetrics.totalSets
    }

    /// Count of sets with data entered (reps > 0) - shows workout progress during active workout
    var completedSets: Int {
        cachedMetrics.completedSets
    }

    var totalVolume: Double {
        cachedMetrics.totalVolume
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

    private var currentExerciseNameSet: Set<String> {
        Set(entries.map { $0.exerciseName.lowercased() })
    }

    /// Suggestions that are not currently in this workout, ranked for next-best fit.
    var availableSuggestions: [ExerciseSuggestion] {
        let filtered = exerciseSuggestions.filter { !currentExerciseNameSet.contains($0.exerciseName.lowercased()) }
        guard !filtered.isEmpty else { return [] }

        let recentMuscleGroups = recentMuscleGroupsFromCurrentWorkout(limit: 2)
        let targetMuscleCounts = currentTargetMuscleCounts()

        return filtered.sorted { lhs, rhs in
            let lhsScore = suggestionScore(
                lhs,
                targetMuscleCounts: targetMuscleCounts,
                recentMuscleGroups: recentMuscleGroups
            )
            let rhsScore = suggestionScore(
                rhs,
                targetMuscleCounts: targetMuscleCounts,
                recentMuscleGroups: recentMuscleGroups
            )
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsUsage = exerciseUsageFrequency[lhs.exerciseName, default: 0]
            let rhsUsage = exerciseUsageFrequency[rhs.exerciseName, default: 0]
            if lhsUsage != rhsUsage {
                return lhsUsage > rhsUsage
            }

            return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
        }
    }

    /// Smart "Up Next" suggestion is the top-ranked available suggestion.
    var upNextSuggestion: ExerciseSuggestion? {
        availableSuggestions.first
    }

    /// Get the muscle group for a workout entry (checks suggestions first, then database)
    private func getMuscleGroup(for entry: LiveWorkoutEntry) -> String? {
        if let cachedMuscle = cachedMuscleGroupByExerciseName[entry.exerciseName] {
            return cachedMuscle
        }

        // First check if it's from our suggestions
        if let suggestion = exerciseSuggestions.first(where: { $0.exerciseName == entry.exerciseName }) {
            cachedMuscleGroupByExerciseName[entry.exerciseName] = suggestion.muscleGroup
            return suggestion.muscleGroup
        }

        // Look up the exercise in the database by name
        guard let modelContext else { return nil }
        let exerciseName = entry.exerciseName
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == exerciseName }
        )
        descriptor.fetchLimit = 1
        if let exercise = try? modelContext.fetch(descriptor).first,
           let muscleGroup = exercise.muscleGroup {
            cachedMuscleGroupByExerciseName[entry.exerciseName] = muscleGroup
            return muscleGroup
        }

        return nil
    }

    /// Group available suggestions by muscle group
    var suggestionsByMuscle: [String: [ExerciseSuggestion]] {
        Dictionary(grouping: availableSuggestions) { $0.muscleGroup }
    }

    private var targetExerciseMuscleGroups: Set<String> {
        Set(workout.muscleGroups.map { $0.toExerciseMuscleGroup.rawValue })
    }

    private func recentMuscleGroupsFromCurrentWorkout(limit: Int) -> Set<String> {
        var recentMuscles = Set<String>()
        let recentEntries = entries.suffix(limit)
        for entry in recentEntries {
            if let muscle = getMuscleGroup(for: entry) {
                recentMuscles.insert(muscle)
            }
        }
        return recentMuscles
    }

    private func currentTargetMuscleCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let muscle = getMuscleGroup(for: entry) else { continue }
            guard targetExerciseMuscleGroups.contains(muscle) else { continue }
            counts[muscle, default: 0] += 1
        }
        return counts
    }

    private func suggestionScore(
        _ suggestion: ExerciseSuggestion,
        targetMuscleCounts: [String: Int],
        recentMuscleGroups: Set<String>
    ) -> Double {
        let usageFrequency = Double(exerciseUsageFrequency[suggestion.exerciseName, default: 0])
        let preferenceScore = log1p(usageFrequency) * 1.5

        let currentTargetCount = targetMuscleCounts[suggestion.muscleGroup, default: 0]
        let coverageScore: Double
        if targetExerciseMuscleGroups.contains(suggestion.muscleGroup) {
            switch currentTargetCount {
            case 0:
                coverageScore = 3.0
            case 1:
                coverageScore = 1.5
            default:
                coverageScore = 0.5
            }
        } else {
            coverageScore = 0.0
        }

        let diversityPenalty = recentMuscleGroups.contains(suggestion.muscleGroup) ? 1.25 : 0.0
        return preferenceScore + coverageScore - diversityPenalty
    }

    // MARK: - Initialization

    init(workout: LiveWorkout, suggestions: [ExerciseSuggestion] = []) {
        self.workout = workout
        // elapsedTime is now computed from workout.startedAt
        self.exerciseSuggestions = suggestions
        refreshEntriesAndMetrics()
    }

    /// Initialize with an existing workout and optional template for suggestions
    convenience init(workout: LiveWorkout, template: WorkoutPlan.WorkoutTemplate?) {
        // Template exercises are intentionally ignored so suggestions can adapt
        // to the user's own exercise history and selected target muscles.
        _ = template
        self.init(workout: workout, suggestions: [])
    }

    // MARK: - Setup

    func setup(with modelContext: ModelContext, healthKitService: HealthKitService? = nil) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService
        usesMetricWeightPreference = getUserUsesMetricWeight()

        // Insert workout if not already persisted
        if workout.modelContext == nil {
            modelContext.insert(workout)
            try? modelContext.save()
            BehaviorTracker(modelContext: modelContext).record(
                actionKey: BehaviorActionKey.startWorkout,
                domain: .workout,
                surface: .workouts,
                outcome: .performed,
                relatedEntityId: workout.id,
                metadata: [
                    "source": "live_workout_setup",
                    "workout_name": workout.name
                ]
            )
        }

        refreshEntriesAndMetrics()
        startTimer()
        loadLastPerformances()
        loadExerciseUsageFrequency()
        rebuildSuggestionPool(reason: .workoutStart)

        // Start heart rate streaming from Apple Watch
        startHeartRateMonitoring()

        // Start Live Activity
        startLiveActivity()
        
        // Set up Live Activity intent observers
        setupLiveActivityObservers()
    }
    
    private func setupLiveActivityObservers() {
        // Poll App Groups UserDefaults for Live Activity button taps
        // This is needed because LiveActivityIntent runs in the widget extension
        liveActivityIntentTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkLiveActivityIntents()
            }
        }
    }
    
    private func checkLiveActivityIntents() {
        guard let defaults = UserDefaults(suiteName: LiveActivityIntentKeys.suiteName) else { return }
        
        // Check for "Add Set" action
        let addSetTimestamp = defaults.double(forKey: LiveActivityIntentKeys.addSetTimestamp)
        if addSetTimestamp > lastAddSetTimestamp {
            lastAddSetTimestamp = addSetTimestamp
            handleAddSetFromLiveActivity()
        }
        
        // Check for "Toggle Pause" action
        let togglePauseTimestamp = defaults.double(forKey: LiveActivityIntentKeys.togglePauseTimestamp)
        if togglePauseTimestamp > lastTogglePauseTimestamp {
            lastTogglePauseTimestamp = togglePauseTimestamp
            handleTogglePauseFromLiveActivity()
        }
    }
    
    private func removeLiveActivityObservers() {
        liveActivityIntentTimer?.invalidate()
        liveActivityIntentTimer = nil
    }
    
    /// Handle "Add Set" button tap from Live Activity
    private func handleAddSetFromLiveActivity() {
        let targetEntry = liveActivityEntryForAddSet()
        guard let targetEntry else { return }

        addSet(to: targetEntry)
        HapticManager.mediumTap()
    }
    
    /// Handle "Pause/Resume" button tap from Live Activity
    private func handleTogglePauseFromLiveActivity() {
        if isTimerRunning {
            pauseTimer()
        } else {
            resumeTimer()
        }
        HapticManager.lightTap()
    }

    // MARK: - Apple Watch Monitoring

    func startHeartRateMonitoring() {
        guard let service = healthKitService else {
            watchSetupErrorMessage = "HealthKit is unavailable on this device."
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await syncWatchData(using: service)
            } catch {
                watchSetupErrorMessage = "Health access is disabled. In Health app, allow Trai to read Heart Rate, Active Energy, and Workouts."
            }
        }
    }

    func retryWatchSync() {
        guard !isRetryingWatchSync else { return }
        guard let service = healthKitService else {
            watchSetupErrorMessage = "HealthKit is unavailable on this device."
            return
        }

        isRetryingWatchSync = true
        watchSetupErrorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isRetryingWatchSync = false }

            do {
                try await syncWatchData(using: service)
            } catch {
                watchSetupErrorMessage = "Health access is disabled. In Health app, allow Trai to read Heart Rate, Active Energy, and Workouts."
            }
        }
    }

    func stopHeartRateMonitoring() {
        healthKitService?.stopHeartRateStreaming()
        healthKitService?.stopCalorieStreaming()
        currentHeartRate = nil
        lastHeartRateUpdate = nil
        watchSetupErrorMessage = nil
    }

    /// Updates heart rate and calories from the HealthKit service - called by the view
    func updateWatchDataFromService() {
        guard let service = healthKitService else { return }
        let latestHeartRate = service.currentHeartRate
        if Int(currentHeartRate ?? -1) != Int(latestHeartRate ?? -1) {
            currentHeartRate = latestHeartRate
        }

        let latestHeartRateUpdate = service.lastHeartRateUpdate
        if lastHeartRateUpdate != latestHeartRateUpdate {
            lastHeartRateUpdate = latestHeartRateUpdate
        }

        let latestCalories = service.workoutCalories
        if Int(workoutCalories) != Int(latestCalories) {
            workoutCalories = latestCalories
        }

        let latestCalorieUpdate = service.lastCalorieUpdate
        if lastCalorieUpdate != latestCalorieUpdate {
            lastCalorieUpdate = latestCalorieUpdate
        }
    }

    /// Legacy method for backwards compatibility
    func updateHeartRateFromService() {
        updateWatchDataFromService()
    }

    private func syncWatchData(using service: HealthKitService) async throws {
        try await service.ensureAuthorization()

        watchSetupErrorMessage = nil
        service.startHeartRateStreaming(from: workout.startedAt)
        service.startCalorieStreaming(from: workout.startedAt)

        // Seed UI immediately with a recent sample while anchored queries warm up.
        if let recentHeartRate = await service.fetchRecentHeartRate(),
           Date().timeIntervalSince(recentHeartRate.date) <= 120 {
            currentHeartRate = recentHeartRate.bpm
            lastHeartRateUpdate = recentHeartRate.date
        }

        updateWatchDataFromService()
    }

    /// Rebuild the session suggestion pool from target muscles.
    /// This is intentionally event-driven (not tied to set/rep/weight edits).
    private func rebuildSuggestionPool(reason _: SuggestionRebuildReason) {
        guard let modelContext else { return }
        guard !workout.targetMuscleGroups.isEmpty else {
            exerciseSuggestions = []
            return
        }

        let targetMuscleTokens = workout.targetMuscleGroups
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let targetMuscles = LiveWorkout.MuscleGroup.fromTargetStrings(targetMuscleTokens)
        guard !targetMuscles.isEmpty else {
            exerciseSuggestions = []
            return
        }

        let exerciseMuscleGroups = Set(targetMuscles.map { $0.toExerciseMuscleGroup.rawValue })
        let descriptor = FetchDescriptor<Exercise>()
        guard let exercises = try? modelContext.fetch(descriptor) else { return }

        // Exclude custom exercises created in this workout session:
        // those are usually being performed immediately, not "next suggestion" candidates.
        let filtered = exercises.filter { exercise in
            guard let muscleGroup = exercise.muscleGroup else { return false }
            guard exerciseMuscleGroups.contains(muscleGroup) else { return false }
            if exercise.isCustom && exercise.createdAt >= workout.startedAt {
                return false
            }
            return true
        }

        let sortedByPreference = filtered.sorted { lhs, rhs in
            let lhsUsage = exerciseUsageFrequency[lhs.name, default: 0]
            let rhsUsage = exerciseUsageFrequency[rhs.name, default: 0]
            if lhsUsage != rhsUsage {
                return lhsUsage > rhsUsage
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        var seenNames = Set<String>()
        let uniqueExercises = sortedByPreference.filter { exercise in
            seenNames.insert(exercise.name.lowercased()).inserted
        }

        let userDefaultReps = getUserDefaultRepCount()
        exerciseSuggestions = Array(uniqueExercises.prefix(maxSuggestionPoolSize)).map { exercise in
            ExerciseSuggestion(
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup ?? "other",
                defaultSets: 3,
                defaultReps: userDefaultReps
            )
        }
        cachedMuscleGroupByExerciseName.removeAll(keepingCapacity: true)
        loadSuggestionPerformances()
    }

    func refreshSuggestions() {
        rebuildSuggestionPool(reason: .userRefresh)
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
        for suggestion in exerciseSuggestions {
            if let lastPerformance = getLastPerformance(for: suggestion.exerciseName) {
                lastPerformances[suggestion.exerciseName] = lastPerformance
            }
        }
    }

    // MARK: - Last Performance & Personal Records

    /// Load last performances for all exercises in the workout
    func loadLastPerformances() {
        for entry in entries {
            _ = getPerformanceSnapshot(for: entry.exerciseName)
        }
    }

    /// Get last performance for a specific exercise
    func getLastPerformance(for exerciseName: String) -> ExerciseHistory? {
        getPerformanceSnapshot(for: exerciseName)?.lastSession
    }

    /// Get personal record (all-time max weight) for a specific exercise
    func getPersonalRecord(for exerciseName: String) -> ExerciseHistory? {
        getPerformanceSnapshot(for: exerciseName)?.weightPR
    }

    private func cachePerformanceSnapshot(_ snapshot: ExercisePerformanceSnapshot, for exerciseName: String) {
        performanceSnapshots[exerciseName] = snapshot
        if let lastSession = snapshot.lastSession {
            lastPerformances[exerciseName] = lastSession
        } else {
            lastPerformances.removeValue(forKey: exerciseName)
        }
        if let weightPR = snapshot.weightPR {
            personalRecords[exerciseName] = weightPR
        } else {
            personalRecords.removeValue(forKey: exerciseName)
        }
    }

    private func clearPerformanceCache(for exerciseName: String) {
        performanceSnapshots.removeValue(forKey: exerciseName)
        lastPerformances.removeValue(forKey: exerciseName)
        personalRecords.removeValue(forKey: exerciseName)
    }

    private func getPerformanceSnapshot(for exerciseName: String) -> ExercisePerformanceSnapshot? {
        if let cached = performanceSnapshots[exerciseName] {
            return cached
        }
        guard let modelContext else { return nil }
        guard let snapshot = performanceService.snapshot(for: exerciseName, modelContext: modelContext) else {
            clearPerformanceCache(for: exerciseName)
            return nil
        }
        cachePerformanceSnapshot(snapshot, for: exerciseName)
        return snapshot
    }

    /// Check if current workout entry exceeds the cached PR (live checking while editing)
    func isNewPR(for entry: LiveWorkoutEntry) -> PRType? {
        // Get best set from current entry
        let completedSets = entry.sets.filter { !$0.isWarmup && $0.reps > 0 }
        guard !completedSets.isEmpty else { return nil }

        let currentBestWeight = completedSets.map(\.weightKg).max() ?? 0
        let currentTotalVolume = completedSets.reduce(0) { $0 + $1.volume }
        let currentBestReps = completedSets.map(\.reps).max() ?? 0
        let snapshot = getPerformanceSnapshot(for: entry.exerciseName)
        let previousWeightPR = snapshot?.weightPR?.bestSetWeightKg ?? 0
        let previousVolumePR = snapshot?.volumePR?.totalVolume ?? 0
        let previousRepsPR = snapshot?.repsPR?.bestSetReps ?? 0

        // First time doing this exercise - consider it a PR if there's weight.
        if snapshot == nil, currentBestWeight > 0 {
            return .weight
        }

        // Check for weight PR
        if currentBestWeight > previousWeightPR {
            return .weight
        }
        // Check for volume PR
        if currentTotalVolume > previousVolumePR {
            return .volume
        }
        // Check for rep PR (at same or higher weight)
        if currentBestReps > previousRepsPR && currentBestWeight >= previousWeightPR {
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
        if pendingSaveTask != nil {
            try? modelContext?.save()
        }
        pendingSaveTask?.cancel()
        pendingLiveActivityUpdateTask?.cancel()
        stopHeartRateMonitoring()
        stopLiveActivityUpdates()
        removeLiveActivityObservers()
    }

    // MARK: - Suggestion Management

    /// Add an exercise from a suggestion
    func addExerciseFromSuggestion(_ suggestion: ExerciseSuggestion) {
        let entry = LiveWorkoutEntry(exerciseName: suggestion.exerciseName, orderIndex: entries.count)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: suggestion.exerciseName)
        _ = getPersonalRecord(for: suggestion.exerciseName)

        // Use first value from user's rep/weight pattern, or fall back to user's default
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
        let suggestedWeightKg = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0
        let cleanWeight = WeightUtility.cleanWeightFromKg(suggestedWeightKg)

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        refreshEntriesAndMetrics()
        saveImmediately()
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
        _ = getPersonalRecord(for: exercise.name)

        // Use first value from user's rep/weight pattern
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
        let suggestedWeightKg = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0
        let cleanWeight = WeightUtility.cleanWeightFromKg(suggestedWeightKg)

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        refreshEntriesAndMetrics()
        saveImmediately()
    }

    func addExerciseByName(_ name: String, exerciseType: String = "strength") {
        let entry = LiveWorkoutEntry(exerciseName: name, orderIndex: entries.count, exerciseType: exerciseType)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: name)
        _ = getPersonalRecord(for: name)

        // Use first value from user's rep/weight pattern
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
        let suggestedWeightKg = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0
        let cleanWeight = WeightUtility.cleanWeightFromKg(suggestedWeightKg)

        // Start with 1 set - user adds more as needed
        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: false,
            isWarmup: false
        ))

        if workout.entries == nil {
            workout.entries = []
        }
        workout.entries?.append(entry)
        refreshEntriesAndMetrics()
        saveImmediately()
    }

    func removeExercise(at index: Int) {
        guard index < entries.count else { return }
        let entry = entries[index]
        workout.entries?.removeAll { $0.id == entry.id }

        // Reorder remaining entries
        for (newIndex, entry) in (workout.entries ?? []).enumerated() {
            entry.orderIndex = newIndex
        }

        refreshEntriesAndMetrics()
        saveImmediately()
    }

    /// Replace an existing exercise with a new one, keeping the same position
    func replaceExercise(_ existingEntry: LiveWorkoutEntry, with newExercise: Exercise) {
        let orderIndex = existingEntry.orderIndex

        // Create new entry with the same order index
        let newEntry = LiveWorkoutEntry(exercise: newExercise, orderIndex: orderIndex)

        // Get last performance to pre-fill first set
        let lastPerformance = getLastPerformance(for: newExercise.name)
        _ = getPersonalRecord(for: newExercise.name)
        let patternReps = lastPerformance?.repPatternArray.first
        let patternWeight = lastPerformance?.weightPatternArray.first

        let suggestedReps = patternReps ?? lastPerformance?.bestSetReps ?? getUserDefaultRepCount()
        let suggestedWeightKg = patternWeight ?? lastPerformance?.bestSetWeightKg ?? 0
        let cleanWeight = WeightUtility.cleanWeightFromKg(suggestedWeightKg)

        // Start with 1 set
        newEntry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
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

        refreshEntriesAndMetrics()
        saveImmediately()
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        var mutableEntries = entries
        mutableEntries.move(fromOffsets: source, toOffset: destination)

        for (index, entry) in mutableEntries.enumerated() {
            entry.orderIndex = index
        }

        refreshEntriesAndMetrics()
        saveImmediately()
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
        let cleanWeight: CleanWeight

        // For weight: prioritize current workout's last set if user modified it
        // This ensures that if user changes weight mid-workout, subsequent sets follow that weight
        if let lastSet, currentSetIndex > 0 {
            // Check if user changed weight from what the pattern suggested
            let patternWeight = currentSetIndex <= weightPattern.count ? weightPattern[currentSetIndex - 1] : 0
            let userModifiedWeight = abs(lastSet.weightKg - patternWeight) > 0.1

            if userModifiedWeight {
                // User overrode the pattern, follow their lead (use their stored clean values)
                cleanWeight = CleanWeight(kg: lastSet.weightKg, lbs: lastSet.weightLbs)
            } else if currentSetIndex < weightPattern.count {
                // Use pattern weight for this set (pattern is in kg)
                cleanWeight = WeightUtility.cleanWeightFromKg(weightPattern[currentSetIndex])
            } else {
                // Past pattern length, copy last set
                cleanWeight = CleanWeight(kg: lastSet.weightKg, lbs: lastSet.weightLbs)
            }
        } else if currentSetIndex < weightPattern.count {
            cleanWeight = WeightUtility.cleanWeightFromKg(weightPattern[currentSetIndex])
        } else {
            if let lastSet {
                cleanWeight = CleanWeight(kg: lastSet.weightKg, lbs: lastSet.weightLbs)
            } else {
                cleanWeight = .zero
            }
        }

        // For reps: use pattern or copy last set
        if currentSetIndex < repPattern.count {
            suggestedReps = repPattern[currentSetIndex]
        } else {
            suggestedReps = lastSet?.reps ?? getUserDefaultRepCount()
        }

        entry.addSet(LiveWorkoutEntry.SetData(
            reps: suggestedReps,
            weight: cleanWeight,
            completed: false,
            isWarmup: false
        ))
        refreshEntriesAndMetrics()
        saveDebounced(updateLiveActivity: true)
    }

    func updateSet(at index: Int, in entry: LiveWorkoutEntry, reps: Int? = nil, weightKg: Double? = nil, weightLbs: Double? = nil, notes: String? = nil) {
        let sets = entry.sets
        guard index < sets.count else { return }

        var set = sets[index]
        var didChange = false
        if let reps, reps != set.reps {
            set.reps = reps
            didChange = true
        }
        if let weightKg, weightKg != set.weightKg {
            set.weightKg = weightKg
            didChange = true
        }
        if let weightLbs, weightLbs != set.weightLbs {
            set.weightLbs = weightLbs
            didChange = true
        }
        if let notes, notes != set.notes {
            set.notes = notes
            didChange = true
        }
        guard didChange else { return }
        entry.updateSet(at: index, with: set)
        refreshEntriesAndMetrics()
        saveDebounced(updateLiveActivity: true)
    }

    func removeSet(at index: Int, from entry: LiveWorkoutEntry) {
        entry.removeSet(at: index)
        refreshEntriesAndMetrics()
        saveImmediately()
    }

    func toggleWarmup(at index: Int, in entry: LiveWorkoutEntry) {
        let sets = entry.sets
        guard index < sets.count else { return }

        var set = sets[index]
        set.isWarmup.toggle()
        entry.updateSet(at: index, with: set)
        refreshEntriesAndMetrics()
        saveImmediately()
    }

    // MARK: - Cardio Management

    func updateCardioDuration(for entry: LiveWorkoutEntry, seconds: Int) {
        entry.durationSeconds = seconds
        saveDebounced(updateLiveActivity: true)
    }

    func updateCardioDistance(for entry: LiveWorkoutEntry, meters: Double) {
        entry.distanceMeters = meters
        saveDebounced(updateLiveActivity: true)
    }

    func toggleCardioCompletion(for entry: LiveWorkoutEntry) {
        if entry.completedAt != nil {
            entry.completedAt = nil
        } else {
            entry.completedAt = Date()
        }
        refreshEntriesAndMetrics()
        saveImmediately()
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
        rebuildSuggestionPool(reason: .targetMusclesChanged)
        saveImmediately()
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
        refreshEntriesAndMetrics()

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

        if let modelContext {
            BehaviorTracker(modelContext: modelContext).record(
                actionKey: BehaviorActionKey.completeWorkout,
                domain: .workout,
                surface: .workouts,
                outcome: .completed,
                relatedEntityId: workout.id,
                metadata: [
                    "workout_name": workout.name,
                    "workout_type": workout.workoutType
                ],
                saveImmediately: false
            )
        }

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

    /// Get user's weight unit preference from their profile
    private func getUserUsesMetricWeight() -> Bool {
        guard let modelContext else { return true }
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            return profile.usesMetricExerciseWeight
        }
        return true // Fallback default (metric)
    }

    func cancelWorkout() {
        stopTimer()
        // End Live Activity immediately (no summary)
        liveActivityManager.endActivity(showSummary: false)
        modelContext?.delete(workout)
        try? modelContext?.save()
    }

    // MARK: - Private Methods

    private func refreshEntriesAndMetrics() {
        let sortedEntries = (workout.entries ?? []).sorted { $0.orderIndex < $1.orderIndex }
        cachedEntries = sortedEntries
        cachedMetrics = calculateMetrics(for: sortedEntries)
    }

    private func calculateMetrics(for entries: [LiveWorkoutEntry]) -> WorkoutMetrics {
        var totalSets = 0
        var completedSetsWithData = 0
        var totalVolume = 0.0

        for entry in entries {
            let sets = entry.sets
            totalSets += sets.count
            for set in sets where !set.isWarmup {
                if set.reps > 0 {
                    completedSetsWithData += 1
                }
                if set.completed {
                    totalVolume += set.volume
                }
            }
        }

        return WorkoutMetrics(
            totalSets: totalSets,
            completedSets: completedSetsWithData,
            totalVolume: totalVolume
        )
    }

    private func createExerciseHistoryEntries() {
        for entry in entries {
            guard entry.completedSets?.isEmpty == false else { continue }

            let history = ExerciseHistory(from: entry, performedAt: workout.completedAt ?? Date())
            modelContext?.insert(history)

            // Check for PRs against canonical per-metric records.
            let previousSnapshot = getPerformanceSnapshot(for: entry.exerciseName)
            let previousWeight = previousSnapshot?.weightPR?.bestSetWeightKg ?? 0
            let previousVolume = previousSnapshot?.volumePR?.totalVolume ?? 0
            let previousReps = Double(previousSnapshot?.repsPR?.bestSetReps ?? 0)
            let hasHistory = (previousSnapshot?.totalSessions ?? 0) > 0

            if history.bestSetWeightKg > previousWeight {
                achievedPRs[entry.exerciseName] = PRValue(
                    type: .weight,
                    exerciseName: entry.exerciseName,
                    newValue: history.bestSetWeightKg,
                    previousValue: previousWeight,
                    isFirstTime: !hasHistory || previousWeight <= 0
                )
            }
            // Volume PR (only if no weight PR already detected)
            else if history.totalVolume > previousVolume,
                    achievedPRs[entry.exerciseName] == nil {
                achievedPRs[entry.exerciseName] = PRValue(
                    type: .volume,
                    exerciseName: entry.exerciseName,
                    newValue: history.totalVolume,
                    previousValue: previousVolume,
                    isFirstTime: false
                )
            }
            // Rep PR (only if nothing else detected)
            else if Double(history.bestSetReps) > previousReps,
                    achievedPRs[entry.exerciseName] == nil {
                achievedPRs[entry.exerciseName] = PRValue(
                    type: .reps,
                    exerciseName: entry.exerciseName,
                    newValue: Double(history.bestSetReps),
                    previousValue: previousReps,
                    isFirstTime: false
                )
            }
        }
    }

    func save() {
        saveImmediately()
    }

    private func saveImmediately(updateLiveActivity: Bool = true) {
        pendingSaveTask?.cancel()
        try? modelContext?.save()
        if updateLiveActivity {
            scheduleLiveActivityUpdate()
        }
    }

    private func saveDebounced(updateLiveActivity: Bool = true) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.saveDebounceDelay)
            try? self.modelContext?.save()
            if updateLiveActivity {
                self.scheduleLiveActivityUpdate()
            }
        }
    }

    private func scheduleLiveActivityUpdate() {
        pendingLiveActivityUpdateTask?.cancel()
        pendingLiveActivityUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.liveActivityDebounceDelay)
            self.updateLiveActivity()
        }
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

    private func hasLoggedSetData(_ set: LiveWorkoutEntry.SetData) -> Bool {
        set.reps > 0
    }

    private func isEntryStartedForLiveActivity(_ entry: LiveWorkoutEntry) -> Bool {
        if entry.isCardio {
            return entry.completedAt != nil
                || (entry.durationSeconds ?? 0) > 0
                || (entry.distanceMeters ?? 0) > 0
        }
        return entry.sets.contains { hasLoggedSetData($0) }
    }

    private func isEntryCompleteForLiveActivity(_ entry: LiveWorkoutEntry) -> Bool {
        if entry.isCardio {
            return entry.completedAt != nil
        }

        let workingSets = entry.sets.filter { !$0.isWarmup }
        guard !workingSets.isEmpty else { return false }
        return workingSets.allSatisfy { hasLoggedSetData($0) }
    }

    private func liveActivityCurrentEntry() -> LiveWorkoutEntry? {
        entries.first { !isEntryCompleteForLiveActivity($0) } ?? entries.last
    }

    private func liveActivityEntryForAddSet() -> LiveWorkoutEntry? {
        if let currentEntry = liveActivityCurrentEntry(), !currentEntry.isCardio {
            return currentEntry
        }

        // If the current item is cardio, route "Add Set" to the next unresolved strength exercise.
        return entries.first { !$0.isCardio && !isEntryCompleteForLiveActivity($0) }
            ?? entries.last(where: { !$0.isCardio })
    }

    private func updateLiveActivity() {
        // Track progression from logged data (or cardio completion), not the legacy set.completed flag.
        let currentEntry = liveActivityCurrentEntry()

        let currentExercise = currentEntry?.exerciseName
        let currentEquipment = currentEntry?.equipmentName

        // Prefer latest logged working set; if none, fall back to the latest logged set.
        // Use both kg and lbs values to avoid rounding errors (200 lbs → 199 bug)
        let currentSet = currentEntry?.sets.last { !$0.isWarmup && hasLoggedSetData($0) }
            ?? currentEntry?.sets.last { hasLoggedSetData($0) }
        let currentWeightKg = currentSet?.weightKg
        let currentWeightLbs = currentSet?.weightLbs
        let currentReps = currentSet?.reps

        // Calculate total volume in both units
        let totalVolumeKg = totalVolume
        let totalVolumeLbs = totalVolume * 2.20462

        // Find next exercise (first after current that isn't started yet)
        let currentIndex = entries.firstIndex { $0.id == currentEntry?.id } ?? -1
        let nextExercise = entries.dropFirst(currentIndex + 1)
            .first { !isEntryStartedForLiveActivity($0) }?
            .exerciseName

        liveActivityManager.updateActivity(
            elapsedSeconds: Int(elapsedTime),
            currentExercise: currentExercise,
            currentEquipment: currentEquipment,
            completedSets: completedSets,
            totalSets: totalSets,
            heartRate: currentHeartRate.map { Int($0) },
            isPaused: !isTimerRunning,
            currentWeightKg: currentWeightKg,
            currentWeightLbs: currentWeightLbs,
            currentReps: currentReps,
            totalVolumeKg: totalVolumeKg,
            totalVolumeLbs: totalVolumeLbs,
            nextExercise: nextExercise,
            usesMetricWeight: usesMetricWeightPreference
        )
    }
}
