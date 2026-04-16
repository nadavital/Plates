//
//  DashboardHelperComponents.swift
//  Trai
//
//  Helper components for dashboard cards
//

import SwiftUI

// MARK: - Macro Ring Item

struct MacroRingItem: View {
    let name: String
    var compactLabel: String? = nil
    let current: Double
    let goal: Double
    let color: Color
    var diameter: CGFloat = 60
    var prefersCompactLabel: Bool = false

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        min(current / goal, 1.0)
    }

    private var labelText: String {
        if prefersCompactLabel, let compactLabel, !compactLabel.isEmpty {
            return compactLabel
        }
        return name
    }

    var body: some View {
        VStack(spacing: TraiSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        TraiGradient.ring(color),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.3), radius: 3, y: 1)

                Text("\(Int(current))g")
                    .font(.traiLabel(diameter < 54 ? 11 : 12))
                    .bold()
            }
            .frame(width: diameter, height: diameter)

            Text(labelText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(prefersCompactLabel ? 0.9 : 0.7)
        }
        .onAppear {
            withAnimation(TraiAnimation.bouncy) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(TraiAnimation.bouncy) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    var subtitle: String?
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.lightTap()
            action()
        } label: {
            VStack(spacing: TraiSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            TraiGradient.actionVibrant(
                                color,
                                color.opacity(0.7)
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: color.opacity(0.3), radius: 6, y: 3)

                    Image(systemName: icon)
                        .font(.body)
                        .bold()
                        .foregroundStyle(.white)
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.traiLabel())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.08))
            .clipShape(.rect(cornerRadius: TraiRadius.medium))
        }
        .buttonStyle(TraiPressStyle(scale: 0.93))
    }
}

struct ChatWithTraiCard: View {
    let isUnlocked: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.lightTap()
            action()
        } label: {
            HStack(spacing: TraiSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            TraiGradient.actionVibrant(
                                .accentColor,
                                .accentColor.opacity(0.7)
                            )
                        )
                        .frame(width: 30, height: 30)

                    Image(systemName: "circle.hexagongrid.circle")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text("Chat with Trai")
                            .font(.traiHeadline(14))

                        if !isUnlocked {
                            Text("PRO")
                                .font(.traiLabel(10))
                                .foregroundStyle(TraiColors.ember)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(TraiColors.ember.opacity(0.10), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Chat")
                            .font(.traiHeadline(14))

                        if !isUnlocked {
                            Text("PRO")
                                .font(.traiLabel(10))
                                .foregroundStyle(TraiColors.ember)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
            )
            .shadow(color: Color.accentColor.opacity(0.20), radius: 6, y: 2)
        }
        .buttonStyle(TraiPressStyle(scale: 0.96))
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
            .accessibilityIdentifier("dashboardDatePreviousButton")

            Spacer()

            VStack(spacing: 2) {
                Text(dateText)
                    .font(.headline)
                    .accessibilityIdentifier("dashboardDateLabel")

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
                    .accessibilityIdentifier("dashboardJumpToTodayButton")
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
            .accessibilityIdentifier("dashboardDateNextButton")
            .disabled(isToday)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
