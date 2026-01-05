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
    @AppStorage("pendingCheckIn") private var pendingCheckIn = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: .dashboard) {
                DashboardView(onStartCheckIn: navigateToTrai)
            }

            Tab("Trai", systemImage: "circle.hexagongrid.circle", value: .trai, role: .search) {
                ChatView()
            }

            Tab("Workouts", systemImage: "figure.run", value: .workouts) {
                WorkoutsView()
            }
        }
        .onAppear {
            if pendingCheckIn {
                pendingCheckIn = false
                selectedTab = .trai
            }
        }
    }

    private func navigateToTrai() {
        selectedTab = .trai
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
