//
//  ProfileView+Cards.swift
//  Plates
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
    func memoriesCard() -> some View {
        NavigationLink {
            AllMemoriesView()
        } label: {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 40, height: 40)
                    .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

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
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
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
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preferences Card

    @ViewBuilder
    func preferencesCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("Preferences", systemImage: "gearshape.fill")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 0) {
                // Macro Tracking row
                Button {
                    showMacroTrackingSheet = true
                } label: {
                    PreferenceRow(
                        icon: "chart.pie.fill",
                        iconColor: .purple,
                        title: "Macro Tracking",
                        value: macroTrackingSummary(profile),
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 56)

                // Body weight units row
                PreferenceRow(
                    icon: "scalemass.fill",
                    iconColor: .blue,
                    title: "Body Weight",
                    value: nil,
                    showChevron: false
                ) {
                    Picker("Body Weight", selection: Binding(
                        get: { profile.usesMetricWeight },
                        set: {
                            profile.usesMetricWeight = $0
                            profile.usesMetricHeight = $0
                            HapticManager.lightTap()
                        }
                    )) {
                        Text("kg").tag(true)
                        Text("lbs").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }

                Divider()
                    .padding(.leading, 56)

                // Exercise weight units row
                PreferenceRow(
                    icon: "dumbbell.fill",
                    iconColor: .orange,
                    title: "Exercise Weight",
                    value: nil,
                    showChevron: false
                ) {
                    Picker("Exercise Weight", selection: Binding(
                        get: { profile.usesMetricExerciseWeight },
                        set: {
                            profile.usesMetricExerciseWeight = $0
                            HapticManager.lightTap()
                        }
                    )) {
                        Text("kg").tag(true)
                        Text("lbs").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            }
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Helpers

    func macroTrackingSummary(_ profile: UserProfile) -> String {
        let count = profile.enabledMacros.count
        if count == 0 {
            return "Calories only"
        } else if count == 5 {
            return "All macros"
        } else {
            return "\(count) macros"
        }
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
}
