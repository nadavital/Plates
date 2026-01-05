//
//  ProfileView.swift
//  Plates
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    let onStartCheckIn: () -> Void

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

    @Environment(\.modelContext) private var modelContext
    @State private var planService = PlanService()
    @State private var showPlanSheet = false
    @State private var showEditSheet = false

    private var profile: UserProfile? { profiles.first }

    private var hasWorkoutToday: Bool {
        planService.isTrainingDay(workouts: workouts)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let profile {
                        headerCard(profile)
                        statsGrid(profile)
                        planCard(profile)
                        checkInCard(profile)
                        memoriesCard()
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
            // Avatar with gradient ring
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

            // Today's status pill
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

                // Show target weight or a "Set Goal" card
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

            // Calorie display
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

            // Macro pills
            HStack(spacing: 12) {
                MacroPill(label: "Protein", value: profile.dailyProteinGoal, unit: "g", color: .blue)
                MacroPill(label: "Carbs", value: profile.dailyCarbsGoal, unit: "g", color: .green)
                MacroPill(label: "Fat", value: profile.dailyFatGoal, unit: "g", color: .yellow)
            }

            // Weight change prompt
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

    // MARK: - Check-In Card

    @ViewBuilder
    private func checkInCard(_ profile: UserProfile) -> some View {
        let status = planService.getCheckInStatus(for: profile)

        VStack(spacing: 16) {
            HStack {
                Label("Weekly Check-In", systemImage: "calendar.badge.clock")
                    .font(.headline)

                Spacer()

                if status.isDue {
                    Text("Due Today")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green, in: .capsule)
                }
            }

            HStack(spacing: 16) {
                // Day selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-in day")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(UserProfile.Weekday.allCases) { day in
                            Button {
                                profile.checkInDay = day
                                HapticManager.lightTap()
                            } label: {
                                HStack {
                                    Text(day.displayName)
                                    if profile.checkInDay == day {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(profile.checkInDay?.displayName ?? "Select")
                                .fontWeight(.medium)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Spacer()

                if let days = status.daysUntilNext, !status.isDue {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Next in")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(days == 1 ? "1 day" : "\(days) days")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }

            if status.isDue {
                Button {
                    onStartCheckIn()
                } label: {
                    Label("Start Check-In", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    onStartCheckIn()
                } label: {
                    Label("Check in now", systemImage: "arrow.right.circle")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
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
                            AllMemoriesView(memories: memories, onDelete: deleteMemory)
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

    // MARK: - Preferences Card

    @ViewBuilder
    private func preferencesCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            // Units picker
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

            Divider().padding(.leading, 52)

            NavigationLink {
                DietaryRestrictionsView(profile: profile)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                    Text("Dietary Preferences")
                        .font(.subheadline)

                    Spacer()

                    if !profile.dietaryRestrictions.isEmpty {
                        Text("\(profile.dietaryRestrictions.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: .capsule)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct SetGoalCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundStyle(.green)

                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("Set Goal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MacroPill: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DietaryRestrictionsView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        List {
            ForEach(DietaryRestriction.allCases) { restriction in
                Button {
                    toggleRestriction(restriction)
                    HapticManager.lightTap()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: restriction.iconName)
                            .font(.body)
                            .foregroundStyle(profile.dietaryRestrictions.contains(restriction) ? .blue : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(profile.dietaryRestrictions.contains(restriction)
                                          ? Color.blue.opacity(0.15)
                                          : Color.secondary.opacity(0.1))
                            )

                        Text(restriction.displayName)
                            .foregroundStyle(.primary)

                        Spacer()

                        if profile.dietaryRestrictions.contains(restriction) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Dietary Preferences")
    }

    private func toggleRestriction(_ restriction: DietaryRestriction) {
        var restrictions = profile.dietaryRestrictions
        if restrictions.contains(restriction) {
            restrictions.remove(restriction)
        } else {
            restrictions.insert(restriction)
        }
        profile.dietaryRestrictions = restrictions
    }
}

#Preview {
    ProfileView(onStartCheckIn: {})
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
