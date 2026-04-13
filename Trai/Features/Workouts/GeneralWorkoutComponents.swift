//
//  GeneralWorkoutComponents.swift
//  Trai
//

import SwiftUI

struct GeneralSessionOverviewCard: View {
    let workout: LiveWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: workout.type.iconName)
                    .font(.title3)
                    .foregroundStyle(workout.type == .custom ? .secondary : Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.type.displayName)
                        .font(.headline)

                    Text("Flexible session workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !workout.focusAreas.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(workout.focusAreas, id: \.self) { focus in
                        Text(focus)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }

            Text("Track notes, log activities as you go, and ask Trai questions with full session context.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct SessionNotesCard: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session Notes", systemImage: "note.text")
                .font(.headline)

            Text("Capture cues, observations, route grades, flow notes, or anything you want Trai to understand.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $notes)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct GeneralActivityCard: View {
    let entry: LiveWorkoutEntry
    var allowsCompletionToggle: Bool = true
    var allowsDeletion: Bool = true
    var showsEditableFields: Bool = true
    let onUpdateNotes: (String) -> Void
    let onUpdateDuration: (Int?) -> Void
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

    private var durationMinutesBinding: Binding<String> {
        Binding(
            get: {
                guard let seconds = entry.durationSeconds, seconds > 0 else { return "" }
                return String(seconds / 60)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    onUpdateDuration(nil)
                    return
                }
                onUpdateDuration(Int(trimmed).map { $0 * 60 })
            }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { entry.notes },
            set: onUpdateNotes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.activityIconName)
                    .font(.subheadline)
                    .foregroundStyle(entry.completedAt != nil ? .green : .secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.exerciseName)
                        .font(.headline)

                    if let completedAt = entry.completedAt {
                        Text("Completed \(completedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("In progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if allowsCompletionToggle {
                    Button(action: onToggleComplete) {
                        Image(systemName: entry.completedAt != nil ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(entry.completedAt != nil ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                if allowsDeletion {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsEditableFields {
                HStack(spacing: 10) {
                    Label("Duration", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Minutes", text: durationMinutesBinding)
                        .keyboardType(.numberPad)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("What did you work on?", text: notesBinding, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let duration = entry.formattedDuration {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(entry.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct AddGeneralActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onAdd: (String, String, Int?) -> Void

    @State private var activityName = ""
    @State private var activityNotes = ""
    @State private var durationMinutes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Activity", systemImage: "square.and.pencil")
                            .font(.headline)

                        TextField("e.g. V4 bouldering, Flow block, Breathing work", text: $activityName)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Duration", systemImage: "clock")
                            .font(.headline)

                        TextField("Minutes (optional)", text: $durationMinutes)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notes", systemImage: "note.text")
                            .font(.headline)

                        TextEditor(text: $activityNotes)
                            .frame(minHeight: 120)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        onAdd(
                            activityName,
                            activityNotes,
                            Int(durationMinutes.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * 60 }
                        )
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(.accentColor)
                }
            }
        }
        .traiSheetBranding()
    }
}
