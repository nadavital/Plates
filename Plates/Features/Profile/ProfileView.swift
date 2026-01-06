//
//  ProfileView.swift
//  Plates
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutSession.loggedAt, order: .reverse)
    private var workouts: [WorkoutSession]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var weightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse)
    private var foodEntries: [FoodEntry]
    @Query(sort: \LiveWorkout.startedAt, order: .reverse)
    private var liveWorkouts: [LiveWorkout]
    @Query(filter: #Predicate<CoachMemory> { $0.isActive }, sort: \CoachMemory.createdAt, order: .reverse)
    private var memories: [CoachMemory]
    @Query(sort: \ChatMessage.timestamp, order: .forward)
    private var allChatMessages: [ChatMessage]

    @Environment(\.modelContext) private var modelContext
    @State private var planService = PlanService()
    @State private var showPlanSheet = false
    @State private var showEditSheet = false

    private var profile: UserProfile? { profiles.first }

    private var hasWorkoutToday: Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return workouts.contains { $0.loggedAt >= startOfDay }
    }

    private var chatSessions: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] {
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
                        statsGrid(profile)
                        planCard(profile)
                        memoriesCard()
                        chatHistoryCard()
                        preferencesCard(profile)
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Profile")
            .sheet(isPresented: $showPlanSheet) {
                if let profile {
                    PlanAdjustmentSheet(profile: profile)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let profile {
                    ProfileEditSheet(profile: profile)
                }
            }
        }
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
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ profile: UserProfile) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Stats")
                    .font(.headline)

                Spacer()

                Button {
                    showEditSheet = true
                } label: {
                    Text("Edit")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    icon: "ruler",
                    label: "Height",
                    value: profile.heightCm.map { "\(Int($0)) cm" } ?? "Not set",
                    color: .blue
                )

                StatCard(
                    icon: "scalemass",
                    label: "Current",
                    value: weightEntries.first.map { String(format: "%.1f kg", $0.weightKg) } ?? "—",
                    color: .purple
                )

                if let target = profile.targetWeightKg {
                    StatCard(
                        icon: "target",
                        label: "Target",
                        value: String(format: "%.1f kg", target),
                        color: .green
                    )
                } else {
                    SetGoalCard {
                        showEditSheet = true
                    }
                }

                StatCard(
                    icon: "flame",
                    label: "Activity",
                    value: profile.activityLevelValue.displayName,
                    color: .orange
                )
            }
        }
    }

    // MARK: - Plan Card

    @ViewBuilder
    private func planCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("Nutrition Plan", systemImage: "chart.pie.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showPlanSheet = true
                } label: {
                    Text("Adjust")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let effectiveCalories = planService.getEffectiveCalories(for: profile, hasWorkoutToday: hasWorkoutToday)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(effectiveCalories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))

                Text("kcal/day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if hasWorkoutToday, let trainingCals = profile.trainingDayCalories, trainingCals != profile.dailyCalorieGoal {
                    Text("+\(trainingCals - profile.dailyCalorieGoal)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: .capsule)
                }
            }

            HStack(spacing: 12) {
                MacroPill(label: "Protein", value: profile.dailyProteinGoal, unit: "g", color: .blue)
                MacroPill(label: "Carbs", value: profile.dailyCarbsGoal, unit: "g", color: .green)
                MacroPill(label: "Fat", value: profile.dailyFatGoal, unit: "g", color: .yellow)
            }

            if let currentWeight = weightEntries.first?.weightKg,
               planService.shouldPromptForRecalculation(profile: profile, currentWeight: currentWeight),
               let diff = planService.getWeightDifference(profile: profile, currentWeight: currentWeight) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Weight changed by %.1f kg", diff))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Consider updating your plan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Update") {
                        showPlanSheet = true
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Memories Card

    @ViewBuilder
    private func memoriesCard() -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("What I Know About You", systemImage: "brain.head.profile")
                    .font(.headline)

                Spacer()

                if !memories.isEmpty {
                    Text("\(memories.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
            }

            if memories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("No memories yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("As you chat with Trai, important things about your preferences and goals will be remembered.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(memories.prefix(5)) { memory in
                        MemoryRow(memory: memory, onDelete: {
                            deleteMemory(memory)
                        })
                    }

                    if memories.count > 5 {
                        NavigationLink {
                            AllMemoriesView()
                        } label: {
                            Text("See all \(memories.count) memories")
                                .font(.subheadline)
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private func deleteMemory(_ memory: CoachMemory) {
        memory.isActive = false
        HapticManager.lightTap()
    }

    // MARK: - Chat History Card

    @ViewBuilder
    private func chatHistoryCard() -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("Chat History", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)

                Spacer()

                if !chatSessions.isEmpty {
                    Text("\(chatSessions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
            }

            if chatSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("No chat history")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Your conversations with Trai will appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(chatSessions.prefix(5), id: \.id) { session in
                        ChatSessionRow(
                            session: session,
                            onDelete: { deleteChatSession(session.id) }
                        )
                    }

                    if chatSessions.count > 5 {
                        NavigationLink {
                            AllChatSessionsView()
                        } label: {
                            Text("See all \(chatSessions.count) chats")
                                .font(.subheadline)
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private func deleteChatSession(_ sessionId: UUID) {
        let messagesToDelete = allChatMessages.filter { $0.sessionId == sessionId }
        for message in messagesToDelete {
            modelContext.delete(message)
        }
        HapticManager.lightTap()
    }

    // MARK: - Preferences Card

    @ViewBuilder
    private func preferencesCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "ruler.fill")
                    .font(.body)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                Text("Units")
                    .font(.subheadline)

                Spacer()

                Picker("Units", selection: Binding(
                    get: { profile.usesMetricWeight },
                    set: {
                        profile.usesMetricWeight = $0
                        profile.usesMetricHeight = $0
                        HapticManager.lightTap()
                    }
                )) {
                    Text("Metric").tag(true)
                    Text("Imperial").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
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
