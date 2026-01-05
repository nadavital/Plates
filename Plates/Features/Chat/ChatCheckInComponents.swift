//
//  ChatCheckInComponents.swift
//  Plates
//
//  Check-in specific components for the chat view
//

import SwiftUI
import Combine

// MARK: - Check-In Stats Header

struct CheckInStatsHeader: View {
    let summary: CheckInService.WeeklySummary

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: summary.weekStartDate)
        let end = formatter.string(from: summary.weekEndDate)
        return "\(start) - \(end)"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Week in Review")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 16) {
                StatPill(
                    value: "\(summary.daysTracked)/7",
                    label: "days",
                    color: summary.daysTracked >= 5 ? .green : .orange
                )

                StatPill(
                    value: "\(summary.averageDailyCalories)",
                    label: "avg cal",
                    color: calorieColor
                )

                StatPill(
                    value: "\(Int(summary.averageProtein))g",
                    label: "protein",
                    color: proteinColor
                )

                if summary.workoutsCompleted > 0 {
                    StatPill(
                        value: "\(summary.workoutsCompleted)",
                        label: "workouts",
                        color: .blue
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var calorieColor: Color {
        let adherence = summary.calorieAdherence
        if adherence >= 0.9 && adherence <= 1.1 {
            return .green
        } else if adherence >= 0.8 && adherence <= 1.2 {
            return .orange
        } else {
            return .red
        }
    }

    private var proteinColor: Color {
        let adherence = summary.proteinAdherence
        if adherence >= 0.9 {
            return .green
        } else if adherence >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Suggested Responses

struct SuggestedResponsesView: View {
    let responses: [CheckInResponseOption]
    let onSelect: (CheckInResponseOption) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(responses) { response in
                Button {
                    onSelect(response)
                } label: {
                    HStack {
                        if let emoji = response.emoji {
                            Text(emoji)
                        }
                        Text(response.label)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TraiLensView(size: 36, state: .thinking, palette: .energy)

            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Check-In Complete Card

struct CheckInCompleteCard: View {
    let summary: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Check-In Complete!")
                    .font(.headline)
                Spacer()
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Text("Continue")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}
