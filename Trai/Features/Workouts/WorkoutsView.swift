//
//  WorkoutsView.swift
//  Trai
//
//  Plan-first workout tab with template-based workout suggestions
//

import SwiftUI
import SwiftData

struct WorkoutsView: View {
    // MARK: - Queries

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    private var allWorkouts: [WorkoutSession]

    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    private var allLiveWorkouts: [LiveWorkout]

    @Query private var allExerciseHistory: [ExerciseHistory]

    /// Completed in-app workouts (LiveWorkout with completedAt set)
    private var completedLiveWorkouts: [LiveWorkout] {
        allLiveWorkouts.filter { $0.completedAt != nil }
    }

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    // MARK: - Services

    @State private var recoveryService = MuscleRecoveryService()
    @State private var templateService = WorkoutTemplateService()

    // MARK: - Computed State

    @State private var recoveryInfo: [MuscleRecoveryService.MuscleRecoveryInfo] = []
    @State private var templateScores: [UUID: (score: Double, reason: String)] = [:]
    @State private var recommendedTemplateId: UUID?

    // MARK: - Sheet States

    @State private var showingPlanSetup = false
    @State private var showingMuscleRecoveryDetail = false
    @State private var showingWorkoutDetail: WorkoutSession?
    @State private var showingLiveWorkoutDetail: LiveWorkout?
    @State private var showingWorkoutSheet = false
    @State private var showingCustomWorkoutSetup = false
    @State private var showingPersonalRecords = false
    @State private var pendingWorkout: LiveWorkout?
    @State private var pendingTemplate: WorkoutPlan.WorkoutTemplate?

    // MARK: - Computed Properties

    private var workoutPlan: WorkoutPlan? {
        userProfile?.workoutPlan
    }

    private var activeWorkout: LiveWorkout? {
        allLiveWorkouts.first { $0.isInProgress }
    }

    /// HealthKit workout IDs that have been merged into LiveWorkouts (exclude from display)
    private var mergedHealthKitIDs: Set<String> {
        Set(allLiveWorkouts.compactMap { $0.mergedHealthKitWorkoutID })
    }

    /// Filter out HealthKit workouts that have been merged into in-app workouts
    private var filteredWorkouts: [WorkoutSession] {
        allWorkouts.filter { workout in
            guard let hkID = workout.healthKitWorkoutID else { return true }
            return !mergedHealthKitIDs.contains(hkID)
        }
    }

    private var workoutsByDate: [(date: Date, workouts: [WorkoutSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredWorkouts) { workout in
            calendar.startOfDay(for: workout.loggedAt)
        }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.date > $1.date }
    }

    /// Completed in-app workouts grouped by date
    private var liveWorkoutsByDate: [(date: Date, workouts: [LiveWorkout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: completedLiveWorkouts) { workout in
            calendar.startOfDay(for: workout.startedAt)
        }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Workout templates section (shows create CTA if no plan)
                    WorkoutTemplatesSection(
                        templates: workoutPlan?.templates ?? [],
                        recoveryScores: templateScores,
                        recommendedTemplateId: recommendedTemplateId,
                        onStartTemplate: startWorkoutFromTemplate,
                        onCreatePlan: workoutPlan == nil ? { showingPlanSetup = true } : nil
                    )

                    // 3b. Quick start custom workout option
                    QuickStartCard {
                        showingCustomWorkoutSetup = true
                    }

                    // 4. Muscle recovery card (compact view)
                    MuscleRecoveryCard(
                        recoveryInfo: recoveryInfo,
                        onTap: { showingMuscleRecoveryDetail = true }
                    )

                    // 5. Recent workout history (includes both in-app and HealthKit workouts)
                    WorkoutHistorySection(
                        workoutsByDate: workoutsByDate,
                        liveWorkoutsByDate: liveWorkoutsByDate,
                        onWorkoutTap: { workout in
                            showingWorkoutDetail = workout
                        },
                        onLiveWorkoutTap: { workout in
                            showingLiveWorkoutDetail = workout
                        },
                        onDelete: deleteWorkout,
                        onDeleteLiveWorkout: deleteLiveWorkout
                    )
                }
                .padding()
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Personal Records", systemImage: "trophy.fill") {
                        showingPersonalRecords = true
                    }
                }
            }
            .refreshable {
                await syncHealthKit()
                loadRecoveryAndScores()
            }
            .task {
                loadRecoveryAndScores()
                await syncHealthKit()
            }
            .onChange(of: workoutPlan) {
                loadRecoveryAndScores()
            }
            .sheet(isPresented: $showingPlanSetup) {
                WorkoutPlanChatFlow()
            }
            .sheet(isPresented: $showingPersonalRecords) {
                PersonalRecordsView()
            }
            .sheet(isPresented: $showingMuscleRecoveryDetail) {
                MuscleRecoveryDetailSheet(recoveryInfo: recoveryInfo)
            }
            .sheet(item: $showingWorkoutDetail) { workout in
                WorkoutDetailSheet(workout: workout)
            }
            .sheet(item: $showingLiveWorkoutDetail) { workout in
                LiveWorkoutDetailSheet(
                    workout: workout,
                    useLbs: !(userProfile?.usesMetricExerciseWeight ?? true)
                )
            }
            .sheet(isPresented: $showingWorkoutSheet) {
                if let workout = pendingWorkout {
                    NavigationStack {
                        LiveWorkoutView(workout: workout, template: pendingTemplate)
                    }
                }
            }
            .sheet(isPresented: $showingCustomWorkoutSetup) {
                CustomWorkoutSetupSheet { name, type, muscles in
                    startCustomWorkout(name: name, type: type, muscles: muscles)
                }
            }
            .onChange(of: showingWorkoutSheet) { _, isShowing in
                if !isShowing {
                    // Clear template when sheet is dismissed
                    pendingTemplate = nil
                }
            }
        }
    }

    // MARK: - Actions

    private func loadRecoveryAndScores() {
        recoveryInfo = recoveryService.getRecoveryStatus(modelContext: modelContext)

        // Score templates if user has a plan
        if let plan = workoutPlan {
            templateScores = recoveryService.scoreTemplates(plan.templates, modelContext: modelContext)
            recommendedTemplateId = recoveryService.getRecommendedTemplateId(plan: plan, modelContext: modelContext)
        }
    }

    private func startWorkoutFromTemplate(_ template: WorkoutPlan.WorkoutTemplate) {
        let muscleGroups = LiveWorkout.MuscleGroup.fromTargetStrings(template.targetMuscleGroups)

        let workout = LiveWorkout(
            name: template.name,
            workoutType: .strength,
            targetMuscleGroups: muscleGroups
        )
        modelContext.insert(workout)
        try? modelContext.save()

        // Store template for suggestions and open the workout sheet
        pendingTemplate = template
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func startCustomWorkout(
        name: String = "Custom Workout",
        type: LiveWorkout.WorkoutType = .strength,
        muscles: [LiveWorkout.MuscleGroup] = []
    ) {
        let workout = LiveWorkout(
            name: name,
            workoutType: type,
            targetMuscleGroups: muscles
        )
        modelContext.insert(workout)
        try? modelContext.save()

        // Open the workout sheet
        pendingWorkout = workout
        showingWorkoutSheet = true
        HapticManager.selectionChanged()
    }

    private func deleteWorkout(_ workout: WorkoutSession) {
        modelContext.delete(workout)
        try? modelContext.save()
    }

    private func deleteLiveWorkout(_ workout: LiveWorkout) {
        // Delete associated ExerciseHistory entries
        if let entries = workout.entries {
            for entry in entries {
                let historyToDelete = allExerciseHistory.filter {
                    $0.sourceWorkoutEntryId == entry.id
                }
                for history in historyToDelete {
                    modelContext.delete(history)
                }
            }
        }

        modelContext.delete(workout)
        try? modelContext.save()
    }

    private func syncHealthKit() async {
        guard let healthKitService else { return }

        do {
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let healthKitWorkouts = try await healthKitService.fetchWorkoutsAuthorized(from: oneMonthAgo, to: Date())

            // Filter out already imported workouts
            let existingIDs = Set(allWorkouts.compactMap { $0.healthKitWorkoutID })
            let newWorkouts = healthKitWorkouts.filter { !existingIDs.contains($0.healthKitWorkoutID ?? "") }

            for workout in newWorkouts {
                modelContext.insert(workout)
            }

            if !newWorkouts.isEmpty {
                try? modelContext.save()
            }

            // Retroactively merge past workouts that weren't merged at completion time
            await mergeUnmergedWorkouts(healthKitWorkouts: healthKitWorkouts, healthKitService: healthKitService)
        } catch {
            // Handle error silently
        }
    }

    /// Retroactively merge completed in-app workouts with HealthKit data
    private func mergeUnmergedWorkouts(
        healthKitWorkouts: [WorkoutSession],
        healthKitService: HealthKitService
    ) async {
        // Find completed workouts without HealthKit merge
        let unmergedWorkouts = completedLiveWorkouts.filter { $0.mergedHealthKitWorkoutID == nil }

        guard !unmergedWorkouts.isEmpty else { return }

        var merged = false
        for workout in unmergedWorkouts {
            if let match = healthKitService.bestOverlappingWorkout(
                for: workout,
                from: healthKitWorkouts,
                searchBufferMinutes: 15
            ) {
                workout.mergedHealthKitWorkoutID = match.healthKitWorkoutID
                if let calories = match.caloriesBurned {
                    workout.healthKitCalories = Double(calories)
                }
                if let avgHR = match.averageHeartRate {
                    workout.healthKitAvgHeartRate = Double(avgHR)
                }
                merged = true
            }
        }

        if merged {
            try? modelContext.save()
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutsView()
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            Exercise.self,
            LiveWorkout.self,
            LiveWorkoutEntry.self,
            ExerciseHistory.self
        ], inMemory: true)
}
