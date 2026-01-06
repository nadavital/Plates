//
//  DashboardView.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
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

    // Sheet presentation state
    @State private var showingLogFood = false
    @State private var showingAddWorkout = false
    @State private var showingLogWeight = false
    @State private var showingCalorieDetail = false
    @State private var showingMacroDetail = false
    @State private var entryToEdit: FoodEntry?
    @State private var sessionIdToAddTo: UUID?

    // Date navigation
    @State private var selectedDate = Date()

    private var profile: UserProfile? { profiles.first }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDayFoodEntries: [FoodEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allFoodEntries.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay }
    }

    private var selectedDayWorkouts: [WorkoutSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allWorkouts.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date Navigation
                    DateNavigationBar(
                        selectedDate: $selectedDate,
                        isToday: isViewingToday
                    )

                    if isViewingToday, let profile {
                        GreetingCard(name: profile.name, goal: profile.goal)

                        // Quick action buttons (only on today)
                        QuickActionsCard(
                            onLogFood: { showingLogFood = true },
                            onAddWorkout: { showingAddWorkout = true },
                            onLogWeight: { showingLogWeight = true }
                        )
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
                        fiber: totalFiber,
                        proteinGoal: profile?.dailyProteinGoal ?? 150,
                        carbsGoal: profile?.dailyCarbsGoal ?? 200,
                        fatGoal: profile?.dailyFatGoal ?? 65,
                        fiberGoal: profile?.dailyFiberGoal ?? 30,
                        onTap: { showingMacroDetail = true }
                    )

                    DailyFoodTimeline(
                        entries: selectedDayFoodEntries,
                        onAddFood: isViewingToday ? { showingLogFood = true } : nil,
                        onAddToSession: isViewingToday ? { sessionId in
                            sessionIdToAddTo = sessionId
                            showingLogFood = true
                        } : nil,
                        onEditEntry: { entryToEdit = $0 },
                        onDeleteEntry: deleteFoodEntry
                    )

                    TodaysActivityCard(workoutCount: selectedDayWorkouts.count)

                    if isViewingToday, let latestWeight = weightEntries.first {
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
                    entries: selectedDayFoodEntries,
                    goal: profile?.dailyCalorieGoal ?? 2000,
                    onAddFood: isViewingToday ? {
                        showingCalorieDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    } : nil,
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
                    entries: selectedDayFoodEntries,
                    proteinGoal: profile?.dailyProteinGoal ?? 150,
                    carbsGoal: profile?.dailyCarbsGoal ?? 200,
                    fatGoal: profile?.dailyFatGoal ?? 65,
                    fiberGoal: profile?.dailyFiberGoal ?? 30,
                    onAddFood: isViewingToday ? {
                        showingMacroDetail = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            showingLogFood = true
                        }
                    } : nil,
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
                        ProfileView()
                    } label: {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var totalCalories: Int {
        selectedDayFoodEntries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        selectedDayFoodEntries.reduce(0) { $0 + $1.fatGrams }
    }

    private var totalFiber: Double {
        selectedDayFoodEntries.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
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
    DashboardView()
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
