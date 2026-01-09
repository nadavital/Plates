//
//  ContentView.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    private var hasCompletedOnboarding: Bool {
        profiles.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Tab View

enum AppTab: String, CaseIterable {
    case dashboard
    case trai
    case workouts
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard
    @Query(filter: #Predicate<LiveWorkout> { $0.completedAt == nil })
    private var activeWorkouts: [LiveWorkout]

    // Capture the workout when opening sheet to avoid nil issues when workout completes
    @State private var presentedWorkout: LiveWorkout?
    @State private var showingEndConfirmation = false

    private var activeWorkout: LiveWorkout? {
        activeWorkouts.first
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: .dashboard) {
                DashboardView()
            }

            Tab("Trai", systemImage: "circle.hexagongrid.circle", value: .trai, role: .search) {
                ChatView()
            }

            Tab("Workouts", systemImage: "figure.run", value: .workouts) {
                WorkoutsView()
            }
        }
        .tabViewBottomAccessory(isEnabled: activeWorkout != nil) {
            if let workout = activeWorkout {
                WorkoutBanner(
                    workout: workout,
                    onTap: { presentedWorkout = workout },
                    onEnd: { showingEndConfirmation = true }
                )
            }
        }
        .sheet(item: $presentedWorkout) { workout in
            NavigationStack {
                LiveWorkoutView(workout: workout)
            }
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                if let workout = activeWorkout {
                    workout.completedAt = Date()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this workout?")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            UserProfile.self,
            FoodEntry.self,
            Exercise.self,
            WorkoutSession.self,
            WeightEntry.self,
            ChatMessage.self,
            LiveWorkout.self,
            LiveWorkoutEntry.self,
            ExerciseHistory.self
        ], inMemory: true)
}
