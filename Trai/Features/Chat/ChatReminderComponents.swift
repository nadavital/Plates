//
//  ChatReminderComponents.swift
//  Trai
//
//  Reminder suggestion UI components for chat
//

import SwiftUI
import SwiftData

// MARK: - Reminder Suggestion Card

struct ReminderSuggestionCard: View {
    let suggestion: SuggestedReminder
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                    Text("Create Reminder?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.quaternarySystemFill))
                        .clipShape(.circle)
                }
            }

            // Reminder details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(suggestion.title)
                        .font(.body)
                        .fontWeight(.medium)
                }

                if !suggestion.body.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "text.alignleft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(suggestion.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(suggestion.formattedTime)
                        .font(.subheadline)
                }

                HStack {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(suggestion.scheduleDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onEdit()
                } label: {
                    Text("Edit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Create Reminder")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Created Reminder Chip

struct CreatedReminderChip: View {
    let suggestion: SuggestedReminder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.caption)
                .foregroundStyle(.blue)

            Text("Reminder created: \(suggestion.title)")
                .font(.caption)
                .fontWeight(.medium)

            Text("at \(suggestion.formattedTime)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .clipShape(.capsule)
    }
}

#Preview {
    VStack {
        ReminderSuggestionCard(
            suggestion: SuggestedReminder(
                title: "Drink water",
                body: "Stay hydrated throughout the day",
                hour: 14,
                minute: 0,
                repeatDays: ""
            ),
            onConfirm: {},
            onEdit: {},
            onDismiss: {}
        )

        CreatedReminderChip(
            suggestion: SuggestedReminder(
                title: "Take vitamins",
                body: "",
                hour: 9,
                minute: 0,
                repeatDays: "2,3,4,5,6"
            )
        )
    }
    .padding()
}
