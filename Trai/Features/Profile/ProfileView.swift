//
//  ProfileView.swift
//  Trai
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query var profiles: [UserProfile]
    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    var workouts: [WorkoutSession]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    var weightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    var foodEntries: [FoodEntry]
    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    var liveWorkouts: [LiveWorkout]
    @Query(filter: #Predicate<CoachMemory> { $0.isActive }, sort: \CoachMemory.createdAt, order: .reverse)
    var memories: [CoachMemory]
    @Query(sort: \ChatMessage.timestamp, order: .forward)
    var allChatMessages: [ChatMessage]

    @Environment(\.modelContext) var modelContext
    @State var showPlanSheet = false
    @State var showSettingsSheet = false
    @State var customRemindersCount = 0

    // Workout plan management sheets
    @State var showPlanSetupSheet = false
    @State var showPlanEditSheet = false
    @State private var lastOpenTrackedAt: Date?

    // For navigating to Trai tab with plan review
    @AppStorage("pendingPlanReviewRequest") var pendingPlanReviewRequest = false
    @AppStorage("pendingWorkoutPlanReviewRequest") var pendingWorkoutPlanReviewRequest = false
    @AppStorage("selectedTab") var selectedTabRaw: String = AppTab.dashboard.rawValue

    var profile: UserProfile? { profiles.first }

    var hasWorkoutToday: Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return workouts.contains { $0.loggedAt >= startOfDay }
    }

    var chatSessions: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] {
        var sessions: [UUID: (firstMessage: String, date: Date, messageCount: Int)] = [:]

        for message in allChatMessages {
            guard let sessionId = message.sessionId else { continue }
            if let existing = sessions[sessionId] {
                sessions[sessionId] = (existing.firstMessage, existing.date, existing.messageCount + 1)
            } else {
                sessions[sessionId] = (message.content, message.timestamp, 1)
            }
        }

        return sessions
            .map { (id: $0.key, firstMessage: $0.value.firstMessage, date: $0.value.date, messageCount: $0.value.messageCount) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let profile {
                        headerCard(profile)
                        planCard(profile)
                        workoutPlanCard(profile)
                        memoriesCard()
                        chatHistoryCard()
                        exercisesCard()
                        remindersCard(profile, customRemindersCount: customRemindersCount)
                    }
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showPlanSheet) {
                if let profile {
                    PlanAdjustmentSheet(profile: profile)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                if let profile {
                    NavigationStack {
                        SettingsView(profile: profile)
                    }
                }
            }
            .sheet(isPresented: $showPlanSetupSheet) {
                WorkoutPlanChatFlow()
            }
            .sheet(isPresented: $showPlanEditSheet) {
                if let plan = profile?.workoutPlan {
                    WorkoutPlanEditSheet(currentPlan: plan)
                }
            }
            .onAppear {
                fetchCustomRemindersCount()
                trackOpenProfileIfNeeded()
            }
        }
        .traiBackground()
    }

    private func fetchCustomRemindersCount() {
        let descriptor = FetchDescriptor<CustomReminder>(
            predicate: #Predicate { $0.isEnabled }
        )
        customRemindersCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func trackOpenProfileIfNeeded() {
        let now = Date()
        if let lastOpenTrackedAt, now.timeIntervalSince(lastOpenTrackedAt) < 8 * 60 {
            return
        }
        lastOpenTrackedAt = now
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.openProfile,
            domain: .profile,
            surface: .profile,
            outcome: .opened,
            metadata: ["source": "profile_tab"]
        )
    }

    // MARK: - Header Card

    @ViewBuilder
    private func headerCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 90, height: 90)

                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Text(profile.name.prefix(1).uppercased())
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    }
            }

            VStack(spacing: 4) {
                Text(profile.name.isEmpty ? "Welcome" : profile.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 6) {
                    Image(systemName: profile.goal.iconName)
                        .font(.caption)
                    Text(profile.goal.displayName)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(hasWorkoutToday ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(hasWorkoutToday ? "Training Day" : "Rest Day")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((hasWorkoutToday ? Color.green : Color.orange).opacity(0.15))
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
    }

}

#Preview {
    ProfileView()
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
