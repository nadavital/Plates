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

                    Text("Activity session")
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

            Text("Log activities and notes with full session context.")
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
    var isPlannedGuidance: Bool = false
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

    private var metadataChips: [ActivityMetadataChip] {
        guard !isPlannedGuidance else { return [] }

        var chips: [ActivityMetadataChip] = []

        func appendUnique(title: String, icon: String) {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty,
                  !chips.contains(where: { $0.title.lowercased() == normalized }) else {
                return
            }
            chips.append(ActivityMetadataChip(title: title, icon: icon))
        }

        if let kind = entry.activityKind {
            appendUnique(title: kind.displayName, icon: kind.iconName)
        }
        if let role = entry.activityRole {
            appendUnique(title: role.displayName, icon: role.iconName)
        }
        if let intensity = entry.plannedIntensity?.trimmingCharacters(in: .whitespacesAndNewlines), !intensity.isEmpty {
            appendUnique(title: intensity, icon: "gauge.with.dots.needle.33percent")
        }
        if let target = entry.plannedTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty,
           !isPlannedGuidance {
            appendUnique(title: target, icon: "target")
        }
        return chips
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPlannedGuidance ? 8 : 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.activityIconName)
                    .font(.subheadline)
                    .foregroundStyle(entry.completedAt != nil ? .green : .secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.exerciseName)
                        .font(isPlannedGuidance ? .subheadline.weight(.semibold) : .headline)

                    if !isPlannedGuidance {
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
                }

                Spacer()

                if allowsCompletionToggle && !isPlannedGuidance {
                    Button(action: onToggleComplete) {
                        Image(systemName: entry.completedAt != nil ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(entry.completedAt != nil ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                if allowsDeletion && !isPlannedGuidance {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !metadataChips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(metadataChips) { chip in
                        Label(chip.title, systemImage: chip.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
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
            } else if !isPlannedGuidance {
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
        .padding(isPlannedGuidance ? 14 : 16)
        .background(Color(.secondarySystemBackground).opacity(isPlannedGuidance ? 0.72 : 1))
        .clipShape(.rect(cornerRadius: isPlannedGuidance ? 14 : 16))
    }
}

private struct ActivityMetadataChip: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct AddGeneralActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onAdd: (String, String, Int?, WorkoutPlan.TrainingBlock.BlockKind, WorkoutPlan.TrainingBlock.Role) -> Void

    @State private var activityName = ""
    @State private var activityNotes = ""
    @State private var durationMinutes = ""
    @State private var selectedKind: WorkoutPlan.TrainingBlock.BlockKind = .custom
    @State private var selectedRole: WorkoutPlan.TrainingBlock.Role = .accessory

    private var addableKinds: [WorkoutPlan.TrainingBlock.BlockKind] {
        [.cardio, .conditioning, .mobility, .skill, .sportPractice, .recovery, .custom]
    }

    private var addableRoles: [WorkoutPlan.TrainingBlock.Role] {
        [.main, .warmup, .accessory, .finisher, .cooldown, .custom]
    }

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

                        HStack(spacing: 10) {
                            Picker("Kind", selection: $selectedKind) {
                                ForEach(addableKinds) { kind in
                                    Label(kind.displayName, systemImage: kind.iconName)
                                        .tag(kind)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Role", selection: $selectedRole) {
                                ForEach(addableRoles) { role in
                                    Label(role.displayName, systemImage: role.iconName)
                                        .tag(role)
                                }
                            }
                            .pickerStyle(.menu)
                        }
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
                            Int(durationMinutes.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * 60 },
                            selectedKind,
                            selectedRole
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
