//
//  DashboardHelperComponents.swift
//  Plates
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

// MARK: - Quick Action Button

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
