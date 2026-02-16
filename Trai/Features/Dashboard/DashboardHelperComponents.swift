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
    let current: Double
    let goal: Double
    let color: Color

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        min(current / goal, 1.0)
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
                    .font(.traiLabel())
                    .bold()
            }
            .frame(width: 60, height: 60)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    @State private var isPressed = false

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

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
