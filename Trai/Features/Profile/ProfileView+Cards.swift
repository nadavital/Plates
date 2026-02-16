//
//  ProfileView+Cards.swift
//  Trai
//
//  Profile view card components (plan, memories, chat history, preferences)
//

import SwiftUI

extension ProfileView {
    // MARK: - Plan Card

    @ViewBuilder
    func planCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nutrition Plan", systemImage: "chart.pie.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Show the user's goal
                    HStack(spacing: 4) {
                        Image(systemName: profile.goal.iconName)
                            .font(.caption2)
                        Text(profile.goal.displayName)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

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

            let effectiveCalories = profile.effectiveCalorieGoal(hasWorkoutToday: hasWorkoutToday)

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

            // Show enabled macros with dynamic grid layout
            let macros = profile.enabledMacrosOrdered
            if !macros.isEmpty {
                let columns = macroGridColumns(for: macros.count)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(macros) { macro in
                        MacroPill(
                            label: macro.displayName,
                            value: profile.goalFor(macro),
                            unit: "g",
                            color: macro.color
                        )
                    }
                }
            }

            HStack(spacing: 12) {
                // Review with Trai button
                Button {
                    pendingPlanReviewRequest = true
                    selectedTabRaw = AppTab.trai.rawValue
                    HapticManager.lightTap()
                } label: {
                    HStack {
                        Image(systemName: "circle.hexagongrid.circle")
                        Text("Review with Trai")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)

                // Plan History link
                NavigationLink {
                    PlanHistoryView()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                }
                .buttonStyle(.bordered)
            }

            if let currentWeight = weightEntries.first?.weightKg,
               profile.shouldPromptForRecalculation(currentWeight: currentWeight),
               let diff = profile.weightDifferenceSincePlan(currentWeight: currentWeight) {
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
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
    }

    // MARK: - Workout Plan Card

    @ViewBuilder
    func workoutPlanCard(_ profile: UserProfile) -> some View {
        if let plan = profile.workoutPlan {
            // Has plan - show detailed card like nutrition plan
            VStack(spacing: 16) {
                // Header with title and adjust button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Workout Plan", systemImage: "figure.strengthtraining.traditional")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Image(systemName: plan.splitType.iconName)
                                .font(.caption2)
                            Text(plan.splitType.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showPlanEditSheet = true
                    } label: {
                        Text("Adjust")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Big stats display
                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(plan.daysPerWeek)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("days/week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text("\(plan.templates.count)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text("workouts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let avgDuration = plan.templates.isEmpty ? nil : plan.templates.map(\.estimatedDurationMinutes).reduce(0, +) / plan.templates.count {
                        VStack(spacing: 2) {
                            Text("~\(avgDuration)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("min avg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Template chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plan.templates.sorted { $0.order < $1.order }) { template in
                            WorkoutPlanChip(template: template)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        pendingWorkoutPlanReviewRequest = true
                        selectedTabRaw = AppTab.trai.rawValue
                        HapticManager.lightTap()
                    } label: {
                        HStack {
                            Image(systemName: "circle.hexagongrid.circle")
                            Text("Review with Trai")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)

                    NavigationLink {
                        WorkoutPlanHistoryView()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("History")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        } else {
            // No plan - show create CTA
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Workout Plan", systemImage: "figure.strengthtraining.traditional")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("No plan created yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // Create plan prompt
                Button {
                    showPlanSetupSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Personalized Plan")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("Let Trai design a training program for your goals")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        }
    }

    // MARK: - Workout Plan Chip

    private func WorkoutPlanChip(template: WorkoutPlan.WorkoutTemplate) -> some View {
        let primaryColor = colorForMuscleGroup(template.targetMuscleGroups.first)

        return HStack(spacing: 6) {
            Circle()
                .fill(primaryColor)
                .frame(width: 8, height: 8)

            Text(template.name)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(primaryColor.opacity(0.15))
        .clipShape(.capsule)
    }

    private func colorForMuscleGroup(_ muscleGroup: String?) -> Color {
        guard let muscle = muscleGroup else { return .gray }
        switch muscle {
        case "chest", "shoulders", "triceps":
            return .orange
        case "back", "biceps":
            return .blue
        case "quads", "hamstrings", "glutes", "calves", "legs":
            return .green
        case "core":
            return .purple
        default:
            return .gray
        }
    }

    // MARK: - Memories Card

    @ViewBuilder
    func memoriesCard() -> some View {
        NavigationLink {
            AllMemoriesView()
        } label: {
            HStack {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
                    .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trai Memories")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(memories.isEmpty ? "No memories yet" : "\(memories.count) memories saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat History Card

    @ViewBuilder
    func chatHistoryCard() -> some View {
        NavigationLink {
            AllChatSessionsView()
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(chatSessions.isEmpty ? "No conversations yet" : "\(chatSessions.count) conversations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        }
        .buttonStyle(.plain)
    }

    /// Calculate grid columns for macro pills based on count
    func macroGridColumns(for count: Int) -> [GridItem] {
        let columnCount: Int
        switch count {
        case 1: columnCount = 1
        case 2: columnCount = 2
        case 3: columnCount = 3
        case 4: columnCount = 2  // 2x2 grid
        default: columnCount = 3  // 5+ uses 3 columns
        }
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }

    // MARK: - Exercises Card

    @ViewBuilder
    func exercisesCard() -> some View {
        NavigationLink {
            CustomExercisesView()
        } label: {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Exercises")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("View and manage your exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reminders Card

    @ViewBuilder
    func remindersCard(_ profile: UserProfile, customRemindersCount: Int) -> some View {
        NavigationLink {
            ReminderSettingsView(profile: profile)
        } label: {
            HStack {
                Image(systemName: "bell.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 40, height: 40)
                    .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(remindersSummary(profile, customCount: customRemindersCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var traiReviewButtonForeground: Color {
        .red
    }

    private var traiReviewButtonBackground: Color {
        Color.red.opacity(0.15)
    }

    func remindersSummary(_ profile: UserProfile, customCount: Int) -> String {
        var builtInCount = 0
        if profile.mealRemindersEnabled { builtInCount += 1 }
        if profile.workoutRemindersEnabled { builtInCount += 1 }
        if profile.weightReminderEnabled { builtInCount += 1 }

        let totalCount = builtInCount + customCount

        if totalCount == 0 {
            return "No reminders set"
        } else if customCount > 0 && builtInCount == 0 {
            return "\(customCount) custom"
        } else if customCount > 0 {
            return "\(totalCount) active"
        } else {
            return "\(builtInCount) enabled"
        }
    }
}
