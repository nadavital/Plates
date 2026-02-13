//
//  LiveWorkoutView.swift
//  Trai
//
//  Full-screen live workout tracking interface
//

import ActivityKit
import SwiftUI
import SwiftData

struct LiveWorkoutView: View {
    // MARK: - Properties

    @State private var viewModel: LiveWorkoutViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Query private var profiles: [UserProfile]

    private var usesMetricExerciseWeight: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    // Heart rate update timer
    @State private var heartRateTimer: Timer?

    // Sheet states
    @State private var showingExerciseList = false
    @State private var showingCancelConfirmation = false
    @State private var showingEndConfirmation = false
    @State private var showingSummary = false
    @State private var showingChat = false
    @State private var showingExerciseReplacement = false
    @State private var entryToReplace: LiveWorkoutEntry?
    @State private var showingLiveActivityDisabledAlert = false
    @State private var showingPulseCheckIn = false

    // MARK: - Initialization

    init(workout: LiveWorkout, template: WorkoutPlan.WorkoutTemplate? = nil) {
        self._viewModel = State(initialValue: LiveWorkoutViewModel(workout: workout, template: template))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if showingSummary {
                    // Show summary inline instead of nested sheet
                    WorkoutSummaryContent(
                        workout: viewModel.workout,
                        achievedPRs: viewModel.achievedPRs,
                        onDismiss: handleSummaryDone
                    )
                } else {
                    workoutContent
                }
            }
            .navigationTitle(showingSummary ? "Summary" : viewModel.workoutName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showingSummary {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            handleSummaryDone()
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showingCancelConfirmation = true
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("End", systemImage: "checkmark") {
                            showingEndConfirmation = true
                        }
                        .tint(.accentColor)
                    }
                }
            }
            .onAppear {
                viewModel.setup(with: modelContext, healthKitService: healthKitService)
                startHeartRateUpdates()
                
                // Check if Live Activities are disabled
                if !ActivityAuthorizationInfo().areActivitiesEnabled {
                    showingLiveActivityDisabledAlert = true
                }
            }
            .onDisappear {
                viewModel.stopTimer()
                stopHeartRateUpdates()
            }
            .sheet(isPresented: $showingExerciseList) {
                ExerciseListView(
                    targetMuscleGroups: viewModel.workout.muscleGroups.map { $0.toExerciseMuscleGroup }
                ) { exercise in
                    viewModel.addExercise(exercise)
                    showingExerciseList = false
                }
            }
            .sheet(isPresented: $showingExerciseReplacement) {
                ExerciseListView(
                    targetMuscleGroups: viewModel.workout.muscleGroups.map { $0.toExerciseMuscleGroup }
                ) { exercise in
                    if let entry = entryToReplace {
                        viewModel.replaceExercise(entry, with: exercise)
                    }
                    entryToReplace = nil
                    showingExerciseReplacement = false
                }
            }
            .sheet(isPresented: $showingPulseCheckIn) {
                PostWorkoutPulseCheckInSheet(
                    onSubmit: savePostWorkoutCheckIn,
                    onSkip: skipPostWorkoutCheckIn
                )
            }
            .sheet(isPresented: $showingChat) {
                NavigationStack {
                    ChatView(workoutContext: buildWorkoutContext())
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", systemImage: "checkmark") {
                                    showingChat = false
                                }
                            }
                        }
                }
            }
            .confirmationDialog(
                "Cancel Workout",
                isPresented: $showingCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel Workout", role: .destructive) {
                    viewModel.cancelWorkout()
                    dismiss()
                }
                Button("Continue Workout", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel this workout? All progress will be lost.")
            }
            .confirmationDialog(
                "End Workout",
                isPresented: $showingEndConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Workout") {
                    viewModel.finishWorkout()
                    withAnimation {
                        showingSummary = true
                    }
                }
                Button("Continue", role: .cancel) {}
            } message: {
                Text("Are you ready to finish this workout?")
            }
            .alert(
                "Live Activity Disabled",
                isPresented: $showingLiveActivityDisabledAlert
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Enable Live Activities in Settings to see workout progress on your Lock Screen and Dynamic Island.")
            }
        }
    }

    // MARK: - Workout Content

    private var workoutContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                let entries = viewModel.entries
                let upNext = viewModel.upNextSuggestion
                let availableSuggestions = viewModel.availableSuggestions
                let suggestionsByMuscle = Dictionary(grouping: availableSuggestions) { $0.muscleGroup }
                let upNextSuggestionID = upNext?.id

                LazyVStack(spacing: 16) {
                    // Timer header with optional watch data
                    WorkoutTimerHeader(
                        workoutStartedAt: viewModel.workout.startedAt,
                        isTimerRunning: viewModel.isTimerRunning,
                        totalPauseDuration: viewModel.totalPauseDuration,
                        totalVolume: viewModel.totalVolume,
                        onTogglePause: {
                            if viewModel.isTimerRunning {
                                viewModel.pauseTimer()
                            } else {
                                viewModel.resumeTimer()
                            }
                        },
                        heartRate: viewModel.isWatchConnected ? viewModel.currentHeartRate : nil,
                        calories: viewModel.isWatchConnected ? viewModel.workoutCalories : nil
                    )

                    if let watchHint = viewModel.watchConnectionHint {
                        Text(watchHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Target muscles selector (editable for custom workouts)
                    MuscleGroupSelector(
                        selectedMuscles: Binding(
                            get: { Set(viewModel.workout.muscleGroups) },
                            set: { viewModel.updateMuscleGroups(Array($0)) }
                        ),
                        isCustomWorkout: viewModel.exerciseSuggestions.isEmpty
                    )

                    // Exercise cards - different UI for strength vs cardio
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if entry.isCardio {
                            CardioExerciseCard(
                                entry: entry,
                                onUpdateDuration: { seconds in
                                    viewModel.updateCardioDuration(for: entry, seconds: seconds)
                                },
                                onUpdateDistance: { meters in
                                    viewModel.updateCardioDistance(for: entry, meters: meters)
                                },
                                onComplete: {
                                    viewModel.toggleCardioCompletion(for: entry)
                                },
                                onDeleteExercise: { viewModel.removeExercise(at: index) }
                            )
                        } else {
                            ExerciseCard(
                                entry: entry,
                                lastPerformance: viewModel.lastPerformances[entry.exerciseName],
                                personalRecord: viewModel.personalRecords[entry.exerciseName],
                                usesMetricWeight: usesMetricExerciseWeight,
                                onAddSet: { viewModel.addSet(to: entry) },
                                onRemoveSet: { setIndex in viewModel.removeSet(at: setIndex, from: entry) },
                                onUpdateSet: { setIndex, reps, weightKg, weightLbs, notes in
                                    viewModel.updateSet(at: setIndex, in: entry, reps: reps, weightKg: weightKg, weightLbs: weightLbs, notes: notes)
                                },
                                onToggleWarmup: { setIndex in viewModel.toggleWarmup(at: setIndex, in: entry) },
                                onDeleteExercise: { viewModel.removeExercise(at: index) },
                                onChangeExercise: {
                                    entryToReplace = entry
                                    showingExerciseReplacement = true
                                }
                            )
                        }
                    }

                    // Up Next suggestion (smart rotation)
                    if let upNext {
                        UpNextSuggestionCard(
                            suggestion: upNext,
                            lastPerformance: viewModel.lastPerformances[upNext.exerciseName],
                            usesMetricWeight: usesMetricExerciseWeight
                        ) {
                            viewModel.addUpNextExercise()
                        }
                    }

                    // More suggestions by muscle group
                    if !availableSuggestions.isEmpty {
                        // Filter out the up next suggestion from the grouped view
                        let filteredSuggestions = suggestionsByMuscle.mapValues { suggestions in
                            guard let upNextSuggestionID else { return suggestions }
                            return suggestions.filter { $0.id != upNextSuggestionID }
                        }.filter { !$0.value.isEmpty }

                        if !filteredSuggestions.isEmpty {
                            SuggestionsByMuscleSection(
                                suggestionsByMuscle: filteredSuggestions,
                                lastPerformances: viewModel.lastPerformances
                            ) { suggestion in
                                viewModel.addExerciseFromSuggestion(suggestion)
                            }
                        }
                    }

                    // Bottom padding for the bar
                    Color.clear.frame(height: 100)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                dismissKeyboard()
            }

            // Bottom bar
            WorkoutBottomBar(
                onAddExercise: { showingExerciseList = true },
                onAskTrai: { showingChat = true }
            )
        }
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleSummaryDone() {
        showingPulseCheckIn = true
    }

    private func startHeartRateUpdates() {
        // Poll every 2 seconds for a snappier live-data UI without per-sample view churn.
        heartRateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                viewModel.updateHeartRateFromService()
            }
        }
    }

    private func stopHeartRateUpdates() {
        heartRateTimer?.invalidate()
        heartRateTimer = nil
    }

    private func buildWorkoutContext() -> GeminiService.WorkoutContext {
        let entries = viewModel.entries

        // Count exercises with ALL sets having data entered as "completed"
        let completedExercises = entries.filter { entry in
            !entry.sets.isEmpty && entry.sets.allSatisfy { $0.reps > 0 }
        }.count

        // Find current exercise (first with sets that don't have data yet)
        let currentExercise = entries.first { entry in
            entry.sets.isEmpty || entry.sets.contains { $0.reps == 0 }
        }?.exerciseName ?? entries.last?.exerciseName  // Default to last if all have data

        // Count sets with data entered (reps > 0) as completed for context
        let setsWithData = entries.reduce(0) { total, entry in
            total + entry.sets.filter { $0.reps > 0 && !$0.isWarmup }.count
        }

        // Calculate volume from sets with data
        let volumeWithData = entries.reduce(0.0) { total, entry in
            total + entry.sets.filter { $0.reps > 0 && !$0.isWarmup }.reduce(0.0) { $0 + $1.volume }
        }

        return GeminiService.WorkoutContext(
            workoutName: viewModel.workoutName,
            elapsedMinutes: Int(viewModel.elapsedTime / 60),
            exercisesCompleted: completedExercises,
            exercisesTotal: entries.count,
            currentExercise: currentExercise,
            setsCompleted: setsWithData,
            totalVolume: volumeWithData,
            targetMuscleGroups: viewModel.targetMuscleGroups
        )
    }

    private func savePostWorkoutCheckIn(_ data: PostWorkoutPulseCheckInData) {
        let normalizedTags = data.selectedTags.filter { !$0.localizedStandardContains("felt great") }
        let hasPainCue = normalizedTags.contains { tag in
            tag.localizedStandardContains("shoulder") ||
            tag.localizedStandardContains("knee") ||
            tag.localizedStandardContains("back")
        }
        let isPainFocused = hasPainCue || data.discomfort >= 4

        let hasUsefulInput = !normalizedTags.isEmpty ||
            !data.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            data.discomfort >= 3
        guard hasUsefulInput else {
            dismiss()
            return
        }

        let domain: CoachSignalDomain
        if isPainFocused {
            domain = .pain
        } else if data.discomfort >= 6 {
            domain = .recovery
        } else {
            domain = .readiness
        }

        let title: String
        if isPainFocused {
            title = "Post-workout discomfort"
        } else if data.discomfort >= 6 {
            title = "High workout strain"
        } else {
            title = "Post-workout readiness"
        }

        var detailParts: [String] = []
        if !normalizedTags.isEmpty {
            detailParts.append("Tags: \(normalizedTags.joined(separator: ", "))")
        }
        detailParts.append("Discomfort: \(data.discomfort)/10")
        if !data.note.isEmpty {
            detailParts.append("Note: \(data.note)")
        }

        _ = CoachSignalService(modelContext: modelContext).addSignal(
            title: title,
            detail: detailParts.joined(separator: ". "),
            source: .workoutCheckIn,
            domain: domain,
            severity: min(max(Double(data.discomfort) / 10.0, 0.2), 1.0),
            confidence: 0.8,
            expiresAfter: isPainFocused ? 72 * 60 * 60 : 48 * 60 * 60
        )

        dismiss()
    }

    private func skipPostWorkoutCheckIn() {
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    LiveWorkoutView(workout: {
        let workout = LiveWorkout(
            name: "Push Day",
            workoutType: .strength,
            targetMuscleGroups: [.chest, .shoulders, .triceps]
        )

        let entry1 = LiveWorkoutEntry(exerciseName: "Bench Press", orderIndex: 0)
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 60, lbs: 132.5), completed: true, isWarmup: true))
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 8, weight: CleanWeight(kg: 80, lbs: 177.5), completed: true, isWarmup: false))
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 6, weight: CleanWeight(kg: 90, lbs: 200), completed: false, isWarmup: false))

        let entry2 = LiveWorkoutEntry(exerciseName: "Overhead Press", orderIndex: 1)
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 40, lbs: 90), completed: false, isWarmup: false))
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 40, lbs: 90), completed: false, isWarmup: false))
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weight: CleanWeight(kg: 40, lbs: 90), completed: false, isWarmup: false))

        workout.entries = [entry1, entry2]
        return workout
    }())
    .modelContainer(for: [LiveWorkout.self, LiveWorkoutEntry.self, Exercise.self], inMemory: true)
}
