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
                .buttonStyle(.traiTertiary(size: .compact, width: 76, height: 32))
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
                VStack(spacing: 8) {
                    ForEach(Array(balancedMacroRows(for: macros).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ForEach(row) { macro in
                                MacroPill(
                                    label: macro.displayName,
                                    value: profile.goalFor(macro),
                                    unit: "g",
                                    color: macro.color
                                )
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                // Review with Trai button
                Button {
                    if canAccessAIFeatures {
                        pendingPlanReviewRequest = true
                        onSelectTab?(.trai)
                    } else {
                        proUpsellCoordinator?.present(source: .nutritionPlan)
                    }
                    HapticManager.lightTap()
                } label: {
                    aiActionButtonLabel(
                        isUnlocked: canAccessAIFeatures,
                        unlockedTitle: "Review with Trai"
                    )
                }
                .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fullWidth: true, height: 40))

                // Plan History link
                NavigationLink {
                    PlanHistoryView()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiTertiary(size: .compact, width: 96, height: 40))
            }

            if let currentWeight = latestWeightForPlanPrompt,
               profile.shouldPromptForRecalculation(currentWeight: currentWeight),
               let diff = profile.weightDifferenceSincePlan(currentWeight: currentWeight) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

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
                    .buttonStyle(.traiPrimary(color: .accentColor, size: .compact, width: 76, height: 32))
                    .controlSize(.small)
                }
                .padding()
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .traiCard(cornerRadius: 20, contentPadding: 0)
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
                    .buttonStyle(.traiTertiary(size: .compact, width: 76, height: 32))
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
                            .foregroundStyle(Color.accentColor)
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
                        if canAccessAIFeatures {
                            pendingWorkoutPlanReviewRequest = true
                            onSelectTab?(.trai)
                        } else {
                            proUpsellCoordinator?.present(source: .workoutPlan)
                        }
                        HapticManager.lightTap()
                    } label: {
                        aiActionButtonLabel(
                            isUnlocked: canAccessAIFeatures,
                            unlockedTitle: "Review with Trai"
                        )
                    }
                    .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fullWidth: true, height: 40))

                    NavigationLink {
                        WorkoutPlanHistoryView()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("History")
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiTertiary(size: .compact, width: 96, height: 40))
                }
            }
            .padding(20)
            .traiCard(cornerRadius: 20, contentPadding: 0)
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
                    if canAccessAIFeatures {
                        showPlanSetupSheet = true
                    } else {
                        proUpsellCoordinator?.present(source: .workoutPlan)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.circle")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)

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

                        if !canAccessAIFeatures {
                            Text("PRO")
                                .font(.traiLabel(11))
                                .foregroundStyle(TraiColors.ember)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(TraiColors.ember.opacity(0.10), in: Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .traiCard(cornerRadius: 20, contentPadding: 0)
        }
    }

    // MARK: - Workout Plan Chip

    private func WorkoutPlanChip(template: WorkoutPlan.WorkoutTemplate) -> some View {
        let primaryColor = template.displayAccentColor

        return HStack(spacing: 6) {
            Image(systemName: template.sessionType.iconName)
                .font(.caption2)
                .foregroundStyle(primaryColor)

            Text(template.name)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(primaryColor.opacity(0.15))
        .clipShape(.capsule)
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

                    Text(memoryCount == 0 ? "No memories yet" : "\(memoryCount) memories saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .traiCard(cornerRadius: 16, contentPadding: 0)
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
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(conversationCount == 0 ? "No conversations yet" : "\(conversationCount) conversations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .traiCard(cornerRadius: 16, contentPadding: 0)
        }
        .buttonStyle(.plain)
    }

    func balancedMacroRows(for macros: [MacroType]) -> [[MacroType]] {
        switch macros.count {
        case 0...3:
            [macros]
        case 4:
            [Array(macros.prefix(2)), Array(macros.suffix(2))]
        case 5:
            [Array(macros.prefix(3)), Array(macros.suffix(2))]
        default:
            stride(from: 0, to: macros.count, by: 3).map { start in
                Array(macros[start..<min(start + 3, macros.count)])
            }
        }
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
            .traiCard(cornerRadius: 16, contentPadding: 0)
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
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

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
            .traiCard(cornerRadius: 16, contentPadding: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func aiActionButtonLabel(isUnlocked: Bool, unlockedTitle: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.circle")
                Text(unlockedTitle)
                if !isUnlocked {
                    Text("PRO")
                        .font(.traiLabel(10))
                        .foregroundStyle(TraiColors.ember)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(TraiColors.ember.opacity(0.10), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.circle")
                Text("Review")
                if !isUnlocked {
                    Text("PRO")
                        .font(.traiLabel(10))
                        .foregroundStyle(TraiColors.ember)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
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
