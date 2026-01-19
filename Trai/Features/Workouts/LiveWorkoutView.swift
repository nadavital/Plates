//
//  LiveWorkoutView.swift
//  Trai
//
//  Full-screen live workout tracking interface
//

import SwiftUI
import SwiftData

struct LiveWorkoutView: View {
    // MARK: - Properties

    @State private var viewModel: LiveWorkoutViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    private var usesMetricExerciseWeight: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    // Sheet states
    @State private var showingExerciseList = false
    @State private var showingCancelConfirmation = false
    @State private var showingEndConfirmation = false
    @State private var showingSummary = false
    @State private var showingChat = false

    // MARK: - Initialization

    init(workout: LiveWorkout, template: WorkoutPlan.WorkoutTemplate? = nil) {
        self._viewModel = State(initialValue: LiveWorkoutViewModel(workout: workout, template: template))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Timer header (uses TimelineView for scroll performance)
                        WorkoutTimerHeader(
                            workoutName: viewModel.workoutName,
                            workoutStartedAt: viewModel.workout.startedAt,
                            isTimerRunning: viewModel.isTimerRunning,
                            totalPauseDuration: viewModel.totalPauseDuration,
                            totalSets: viewModel.totalSets,
                            completedSets: viewModel.completedSets,
                            totalVolume: viewModel.totalVolume
                        )

                        // Target muscles selector (editable for custom workouts)
                        MuscleGroupSelector(
                            selectedMuscles: Binding(
                                get: { Set(viewModel.workout.muscleGroups) },
                                set: { viewModel.updateMuscleGroups(Array($0)) }
                            ),
                            isCustomWorkout: viewModel.exerciseSuggestions.isEmpty
                        )

                        // Exercise cards - different UI for strength vs cardio
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
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
                                    lastPerformance: viewModel.getLastPerformance(for: entry.exerciseName),
                                    personalRecord: viewModel.getPersonalRecord(for: entry.exerciseName),
                                    usesMetricWeight: usesMetricExerciseWeight,
                                    onAddSet: { viewModel.addSet(to: entry) },
                                    onRemoveSet: { setIndex in viewModel.removeSet(at: setIndex, from: entry) },
                                    onUpdateSet: { setIndex, reps, weight, notes in
                                        viewModel.updateSet(at: setIndex, in: entry, reps: reps, weight: weight, notes: notes)
                                    },
                                    onToggleWarmup: { setIndex in viewModel.toggleWarmup(at: setIndex, in: entry) },
                                    onDeleteExercise: { viewModel.removeExercise(at: index) }
                                )
                            }
                        }

                        // Up Next suggestion (smart rotation)
                        if let upNext = viewModel.upNextSuggestion {
                            UpNextSuggestionCard(
                                suggestion: upNext,
                                lastPerformance: viewModel.getLastPerformance(for: upNext.exerciseName),
                                usesMetricWeight: usesMetricExerciseWeight
                            ) {
                                viewModel.addUpNextExercise()
                            }
                        }

                        // More suggestions by muscle group
                        if !viewModel.availableSuggestions.isEmpty {
                            // Filter out the up next suggestion from the grouped view
                            let filteredSuggestions = viewModel.suggestionsByMuscle.mapValues { suggestions in
                                suggestions.filter { $0.id != viewModel.upNextSuggestion?.id }
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

                        // Add exercise button
                        AddExerciseButton {
                            showingExerciseList = true
                        }

                        // Bottom padding for the bar
                        Color.clear.frame(height: 80)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    dismissKeyboard()
                }

                // Bottom bar
                WorkoutBottomBar(
                    onEndWorkout: { showingEndConfirmation = true },
                    onAskTrai: { showingChat = true }
                )
            }
            .navigationTitle(viewModel.workout.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if viewModel.isTimerRunning {
                            viewModel.pauseTimer()
                        } else {
                            viewModel.resumeTimer()
                        }
                    } label: {
                        Image(systemName: viewModel.isTimerRunning ? "pause.circle.fill" : "play.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.accent)
                            .font(.title2)
                    }
                }
            }
            .onAppear {
                viewModel.setup(with: modelContext)
            }
            .onDisappear {
                viewModel.stopTimer()
            }
            .sheet(isPresented: $showingExerciseList) {
                ExerciseListView(
                    targetMuscleGroups: viewModel.workout.muscleGroups.map { $0.toExerciseMuscleGroup }
                ) { exercise in
                    viewModel.addExercise(exercise)
                    showingExerciseList = false
                }
            }
            .sheet(isPresented: $showingSummary) {
                WorkoutSummarySheet(workout: viewModel.workout) {
                    showingSummary = false
                    dismiss()
                }
            }
            .sheet(isPresented: $showingChat) {
                NavigationStack {
                    ChatView(workoutContext: buildWorkoutContext())
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
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
                    showingSummary = true
                }
                Button("Continue", role: .cancel) {}
            } message: {
                Text("Are you ready to finish this workout?")
            }
        }
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 60, completed: true, isWarmup: true))
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 8, weightKg: 80, completed: true, isWarmup: false))
        entry1.addSet(LiveWorkoutEntry.SetData(reps: 6, weightKg: 90, completed: false, isWarmup: false))

        let entry2 = LiveWorkoutEntry(exerciseName: "Overhead Press", orderIndex: 1)
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 40, completed: false, isWarmup: false))
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 40, completed: false, isWarmup: false))
        entry2.addSet(LiveWorkoutEntry.SetData(reps: 10, weightKg: 40, completed: false, isWarmup: false))

        workout.entries = [entry1, entry2]
        return workout
    }())
    .modelContainer(for: [LiveWorkout.self, LiveWorkoutEntry.self, Exercise.self], inMemory: true)
}
