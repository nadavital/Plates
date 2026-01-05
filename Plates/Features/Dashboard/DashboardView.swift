//
//  DashboardView.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    let onStartCheckIn: () -> Void

    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    private var allFoodEntries: [FoodEntry]

    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    private var allWorkouts: [WorkoutSession]

    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    private var liveWorkouts: [LiveWorkout]

    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var weightEntries: [WeightEntry]

    @Environment(\.modelContext) private var modelContext
    @State private var healthKitService = HealthKitService()
    @State private var planService = PlanService()

    // Sheet presentation state
    @State private var showingLogFood = false
    @State private var showingAddWorkout = false
    @State private var showingLogWeight = false
    @State private var showingCalorieDetail = false
    @State private var showingMacroDetail = false
    @State private var entryToEdit: FoodEntry?
    @State private var sessionIdToAddTo: UUID?

    private var profile: UserProfile? { profiles.first }

    private var isCheckInDue: Bool {
        guard let profile else { return false }
        return planService.getCheckInStatus(for: profile).isDue
    }

    private var todaysFoodEntries: [FoodEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allFoodEntries.filter { $0.loggedAt >= startOfDay }
    }

    private var todaysWorkouts: [WorkoutSession] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allWorkouts.filter { $0.loggedAt >= startOfDay }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let profile {
                        GreetingCard(name: profile.name, goal: profile.goal)

                        // Quick action buttons
                        QuickActionsCard(
                            onLogFood: { showingLogFood = true },
                            onAddWorkout: { showingAddWorkout = true },
                            onLogWeight: { showingLogWeight = true }
                        )

                        // Check-in prompt when due
                        if isCheckInDue {
                            CheckInDueCard(onStartCheckIn: onStartCheckIn)
                        }
                    }

                    CalorieProgressCard(
                        consumed: totalCalories,
                        goal: profile?.dailyCalorieGoal ?? 2000,
                        onTap: { showingCalorieDetail = true }
                    )

                    MacroBreakdownCard(
                        protein: totalProtein,
                        carbs: totalCarbs,
                        fat: totalFat,
                        proteinGoal: profile?.dailyProteinGoal ?? 150,
                        carbsGoal: profile?.dailyCarbsGoal ?? 200,
                        fatGoal: profile?.dailyFatGoal ?? 65,
                        onTap: { showingMacroDetail = true }
                    )

                    DailyFoodTimeline(
                        entries: todaysFoodEntries,
                        onAddFood: { showingLogFood = true },
                        onAddToSession: { sessionId in
                            sessionIdToAddTo = sessionId
                            showingLogFood = true
                        },
                        onEditEntry: { entryToEdit = $0 },
                        onDeleteEntry: deleteFoodEntry
                    )

                    TodaysActivityCard(workoutCount: todaysWorkouts.count)

                    if let latestWeight = weightEntries.first {
                        WeightTrendCard(
                            currentWeight: latestWeight.weightKg,
                            targetWeight: profile?.targetWeightKg
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await refreshHealthData()
            }
            .fullScreenCover(isPresented: $showingLogFood) {
                FoodCameraView(sessionId: sessionIdToAddTo)
                    .onDisappear {
                        sessionIdToAddTo = nil
                    }
            }
            .sheet(isPresented: $showingLogWeight) {
                LogWeightSheet()
            }
            .sheet(isPresented: $showingAddWorkout) {
                // TODO: AddWorkoutView - will be implemented in Sprint 4
                Text("Add Workout - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showingCalorieDetail) {
                CalorieDetailSheet(
                    entries: todaysFoodEntries,
                    goal: profile?.dailyCalorieGoal ?? 2000,
                    onAddFood: {
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    },
                    onEditEntry: { entry in
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            entryToEdit = entry
                        }
                    },
                    onDeleteEntry: deleteFoodEntry
                )
            }
            .sheet(isPresented: $showingMacroDetail) {
                MacroDetailSheet(
                    entries: todaysFoodEntries,
                    proteinGoal: profile?.dailyProteinGoal ?? 150,
                    carbsGoal: profile?.dailyCarbsGoal ?? 200,
                    fatGoal: profile?.dailyFatGoal ?? 65,
                    onAddFood: {
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    },
                    onEditEntry: { entry in
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            entryToEdit = entry
                        }
                    }
                )
            }
            .sheet(item: $entryToEdit) { entry in
                EditFoodEntrySheet(entry: entry)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ProfileView(onStartCheckIn: onStartCheckIn)
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var totalCalories: Int {
        todaysFoodEntries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.fatGrams }
    }

    private func refreshHealthData() async {
        // Will be implemented with HealthKit sync
    }

    private func deleteFoodEntry(_ entry: FoodEntry) {
        modelContext.delete(entry)
        HapticManager.success()
    }
}

#Preview {
    DashboardView(onStartCheckIn: {})
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
