//
//  PlanAdjustmentComponents.swift
//  Plates
//
//  Supporting components for the plan adjustment sheet
//

import SwiftUI

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

// MARK: - Macro Adjust Row

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

// MARK: - Optional Calorie Row

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
