//
//  DashboardCards.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI

// MARK: - Greeting Card

struct GreetingCard: View {
    let name: String
    let goal: UserProfile.GoalType

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greeting), \(name)!")
                .font(.title2)
                .bold()

            HStack {
                Image(systemName: goal.iconName)
                Text("Goal: \(goal.displayName)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Calorie Progress Card

struct CalorieProgressCard: View {
    let consumed: Int
    let goal: Int
    var onTap: (() -> Void)?

    private var progress: Double {
        min(Double(consumed) / Double(goal), 1.0)
    }

    private var remaining: Int {
        max(goal - consumed, 0)
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: 16) {
                HStack {
                    Text("Calories")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(consumed) / \(goal)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                ProgressView(value: progress)
                    .tint(progress < 0.8 ? .green : progress < 1.0 ? .orange : .red)

                HStack {
                    VStack(alignment: .leading) {
                        Text("\(consumed)")
                            .font(.title)
                            .bold()
                        Text("consumed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(remaining)")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.green)
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Breakdown Card

struct MacroBreakdownCard: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    var fiber: Double = 0
    let proteinGoal: Int
    let carbsGoal: Int
    let fatGoal: Int
    var fiberGoal: Int = 30
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(spacing: 16) {
                HStack {
                    Text("Macros")
                        .font(.headline)
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 16) {
                    MacroRingItem(
                        name: "Protein",
                        current: protein,
                        goal: Double(proteinGoal),
                        color: .blue
                    )

                    MacroRingItem(
                        name: "Carbs",
                        current: carbs,
                        goal: Double(carbsGoal),
                        color: .orange
                    )

                    MacroRingItem(
                        name: "Fat",
                        current: fat,
                        goal: Double(fatGoal),
                        color: .purple
                    )

                    MacroRingItem(
                        name: "Fiber",
                        current: fiber,
                        goal: Double(fiberGoal),
                        color: .green
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct MacroRingItem: View {
    let name: String
    let current: Double
    let goal: Double
    let color: Color

    private var progress: Double {
        min(current / goal, 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(current))g")
                    .font(.caption)
                    .bold()
            }
            .frame(width: 60, height: 60)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Today's Activity Card

struct TodaysActivityCard: View {
    let workoutCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Activity")
                    .font(.headline)

                Text(workoutCount == 0 ? "No workouts yet" : "\(workoutCount) workout\(workoutCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "figure.run")
                .font(.title)
                .foregroundStyle(.tint)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Weight Trend Card

struct WeightTrendCard: View {
    let currentWeight: Double
    let targetWeight: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Weight")
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currentWeight, format: .number.precision(.fractionLength(1)))
                        .font(.title)
                        .bold()

                    Text("kg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let target = targetWeight {
                    Text("Target: \(target, format: .number.precision(.fractionLength(1))) kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "scalemass.fill")
                .font(.title)
                .foregroundStyle(.tint)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    let onLogFood: () -> Void
    let onAddWorkout: () -> Void
    let onLogWeight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Log Food",
                    icon: "plus.circle.fill",
                    color: .green,
                    action: onLogFood
                )
                QuickActionButton(
                    title: "Add Workout",
                    icon: "figure.run",
                    color: .orange,
                    action: onAddWorkout
                )
                QuickActionButton(
                    title: "Log Weight",
                    icon: "scalemass.fill",
                    color: .blue,
                    action: onLogWeight
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Navigation Bar

struct DateNavigationBar: View {
    @Binding var selectedDate: Date
    let isToday: Bool

    private let calendar = Calendar.current

    private var dateText: String {
        if isToday {
            return "Today"
        }

        let formatter = DateFormatter()
        if calendar.isDate(selectedDate, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "EEEE, MMM d"
        } else {
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        }
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        HStack {
            Button {
                withAnimation {
                    selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                }
                HapticManager.lightTap()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(dateText)
                    .font(.headline)

                if !isToday {
                    Button {
                        withAnimation {
                            selectedDate = Date()
                        }
                        HapticManager.lightTap()
                    } label: {
                        Text("Jump to Today")
                            .font(.caption)
                            .foregroundStyle(.accent)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation {
                    selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                }
                HapticManager.lightTap()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(isToday ? .tertiary : .primary)
                    .frame(width: 44, height: 44)
            }
            .disabled(isToday)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}
