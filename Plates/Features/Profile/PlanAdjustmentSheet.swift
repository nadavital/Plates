//
//  PlanAdjustmentSheet.swift
//  Plates
//

import SwiftUI
import SwiftData

struct PlanAdjustmentSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var goalType: UserProfile.GoalType
    @State private var calories: Int
    @State private var protein: Int
    @State private var carbs: Int
    @State private var fat: Int
    @State private var trainingDayCalories: Int?
    @State private var restDayCalories: Int?
    @State private var showAICoach = false

    /// Available goals (6 instead of 7 - removed "health" as too generic, matching onboarding)
    private var availableGoals: [UserProfile.GoalType] {
        [.loseWeight, .loseFat, .buildMuscle, .recomposition, .maintenance, .performance]
    }

    init(profile: UserProfile) {
        self.profile = profile
        _goalType = State(initialValue: profile.goal)
        _calories = State(initialValue: profile.dailyCalorieGoal)
        _protein = State(initialValue: profile.dailyProteinGoal)
        _carbs = State(initialValue: profile.dailyCarbsGoal)
        _fat = State(initialValue: profile.dailyFatGoal)
        _trainingDayCalories = State(initialValue: profile.trainingDayCalories)
        _restDayCalories = State(initialValue: profile.restDayCalories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // AI Coach prompt
                    aiCoachCard

                    // Goal selection
                    goalSection

                    // Manual adjustments
                    manualAdjustmentsSection

                    // Training/Rest day adjustments
                    trainingDaySection
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Adjust Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAICoach) {
                NavigationStack {
                    ChatView()
                        .navigationTitle("Trai")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showAICoach = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - AI Coach Card

    private var aiCoachCard: some View {
        Button {
            showAICoach = true
        } label: {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Talk to Trai")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Get help adjusting your calories, macros, and goals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goal Section

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Goal", systemImage: "target")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(availableGoals) { goal in
                    GoalOption(
                        goal: goal,
                        isSelected: goalType == goal
                    ) {
                        goalType = goal
                        HapticManager.lightTap()
                    }
                }
            }

            if goalType != profile.goal {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)

                    Text("Changing your goal may affect recommended calories and macros")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Manual Adjustments

    private var manualAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Daily Targets", systemImage: "chart.bar.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                MacroAdjustRow(
                    label: "Calories",
                    value: $calories,
                    unit: "kcal",
                    color: .orange,
                    range: 1000...5000,
                    step: 50
                )

                Divider()

                MacroAdjustRow(
                    label: "Protein",
                    value: $protein,
                    unit: "g",
                    color: .blue,
                    range: 50...400,
                    step: 5
                )

                Divider()

                MacroAdjustRow(
                    label: "Carbs",
                    value: $carbs,
                    unit: "g",
                    color: .green,
                    range: 50...600,
                    step: 5
                )

                Divider()

                MacroAdjustRow(
                    label: "Fat",
                    value: $fat,
                    unit: "g",
                    color: .yellow,
                    range: 20...200,
                    step: 5
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )

            // Macro balance indicator
            macroBalanceIndicator
        }
    }

    private var macroBalanceIndicator: some View {
        let proteinCals = protein * 4
        let carbsCals = carbs * 4
        let fatCals = fat * 9
        let totalMacroCals = proteinCals + carbsCals + fatCals
        let difference = totalMacroCals - calories

        return Group {
            if abs(difference) > 100 {
                HStack(spacing: 8) {
                    Image(systemName: difference > 0 ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(difference > 0 ? .yellow : .blue)

                    Text("Macros add up to \(totalMacroCals) kcal (\(difference > 0 ? "+" : "")\(difference) from target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Training Day Section

    private var trainingDaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Training Day Bonus", systemImage: "flame.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Optional: Eat more on workout days to fuel performance")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                OptionalCalorieRow(
                    label: "Training Day",
                    value: $trainingDayCalories,
                    baseCalories: calories,
                    icon: "figure.run",
                    color: .green
                )

                Divider()

                OptionalCalorieRow(
                    label: "Rest Day",
                    value: $restDayCalories,
                    baseCalories: calories,
                    icon: "bed.double.fill",
                    color: .blue
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        profile.goal = goalType
        profile.dailyCalorieGoal = calories
        profile.dailyProteinGoal = protein
        profile.dailyCarbsGoal = carbs
        profile.dailyFatGoal = fat
        profile.trainingDayCalories = trainingDayCalories
        profile.restDayCalories = restDayCalories
        HapticManager.success()
    }
}

// MARK: - Goal Option

struct GoalOption: View {
    let goal: UserProfile.GoalType
    let isSelected: Bool
    let action: () -> Void

    private var colorForGoal: Color {
        switch goal {
        case .loseWeight: .red
        case .loseFat: .orange
        case .buildMuscle: .blue
        case .recomposition: .purple
        case .maintenance: .gray
        case .performance: .green
        case .health: .pink
        }
    }

    private var shortDescription: String {
        switch goal {
        case .loseWeight: "Reduce overall weight"
        case .loseFat: "Preserve muscle mass"
        case .buildMuscle: "Strength & size gains"
        case .recomposition: "Lose fat, gain muscle"
        case .maintenance: "Keep current weight"
        case .performance: "Optimize for athletics"
        case .health: "Balanced nutrition"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? colorForGoal : Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: goal.iconName)
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }

                VStack(spacing: 4) {
                    Text(goal.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(shortDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? colorForGoal : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Views

struct MacroAdjustRow: View {
    let label: String
    @Binding var value: Int
    let unit: String
    let color: Color
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(label.prefix(1))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                }

            Text(label)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    if value - step >= range.lowerBound {
                        value -= step
                        HapticManager.lightTap()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value <= range.lowerBound ? Color(.tertiaryLabel) : color)
                }
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(width: 60)

                Button {
                    if value + step <= range.upperBound {
                        value += step
                        HapticManager.lightTap()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value >= range.upperBound ? Color(.tertiaryLabel) : color)
                }
                .disabled(value >= range.upperBound)
            }

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30)
        }
    }
}

struct OptionalCalorieRow: View {
    let label: String
    @Binding var value: Int?
    let baseCalories: Int
    let icon: String
    let color: Color

    @State private var isEnabled: Bool
    @State private var localValue: Int

    init(label: String, value: Binding<Int?>, baseCalories: Int, icon: String, color: Color) {
        self.label = label
        self._value = value
        self.baseCalories = baseCalories
        self.icon = icon
        self.color = color
        _isEnabled = State(initialValue: value.wrappedValue != nil)
        _localValue = State(initialValue: value.wrappedValue ?? baseCalories)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 32)

                Text(label)
                    .font(.subheadline)

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, enabled in
                        value = enabled ? localValue : nil
                        HapticManager.lightTap()
                    }
            }

            if isEnabled {
                HStack(spacing: 12) {
                    Button {
                        if localValue > 1000 {
                            localValue -= 50
                            value = localValue
                            HapticManager.lightTap()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(color)
                    }

                    VStack(spacing: 2) {
                        Text("\(localValue)")
                            .font(.headline)
                            .monospacedDigit()

                        let diff = localValue - baseCalories
                        if diff != 0 {
                            Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.caption2)
                                .foregroundStyle(diff > 0 ? .green : .orange)
                        }
                    }
                    .frame(width: 80)

                    Button {
                        if localValue < 5000 {
                            localValue += 50
                            value = localValue
                            HapticManager.lightTap()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(color)
                    }

                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 40)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: UserProfile.self, configurations: config)
    let profile = UserProfile()
    profile.dailyCalorieGoal = 2100
    profile.dailyProteinGoal = 165
    profile.dailyCarbsGoal = 210
    profile.dailyFatGoal = 70

    return PlanAdjustmentSheet(profile: profile)
        .modelContainer(container)
}
