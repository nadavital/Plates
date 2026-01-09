//
//  CustomWorkoutSetupSheet.swift
//  Plates
//
//  Sheet for setting up a custom workout with name, type, and target muscles
//

import SwiftUI

// MARK: - Custom Workout Setup Sheet

struct CustomWorkoutSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (String, LiveWorkout.WorkoutType, [LiveWorkout.MuscleGroup]) -> Void

    @State private var workoutName = ""
    @State private var selectedType: LiveWorkout.WorkoutType = .strength
    @State private var selectedMuscles: Set<LiveWorkout.MuscleGroup> = []

    private var canStart: Bool {
        !workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMuscles.isEmpty
    }

    private var defaultName: String {
        if selectedMuscles.isEmpty {
            return "Custom Workout"
        }
        let muscleNames = selectedMuscles.sorted { $0.displayName < $1.displayName }
            .prefix(3)
            .map { $0.displayName }
            .joined(separator: " + ")
        return muscleNames
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Workout name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("e.g., Arm Day, Push Day", text: $workoutName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Workout type
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            WorkoutTypeButton(
                                type: .strength,
                                isSelected: selectedType == .strength
                            ) { selectedType = .strength }

                            WorkoutTypeButton(
                                type: .cardio,
                                isSelected: selectedType == .cardio
                            ) { selectedType = .cardio }

                            WorkoutTypeButton(
                                type: .mixed,
                                isSelected: selectedType == .mixed
                            ) { selectedType = .mixed }
                        }
                    }

                    // Muscle groups (for strength/mixed)
                    if selectedType != .cardio {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Target Muscle Groups")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Select what you want to train today")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            // Quick presets
                            HStack(spacing: 8) {
                                PresetButton(title: "Push", isSelected: isPushSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.pushMuscles)
                                }
                                PresetButton(title: "Pull", isSelected: isPullSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.pullMuscles)
                                }
                                PresetButton(title: "Legs", isSelected: isLegsSelected) {
                                    togglePreset(LiveWorkout.MuscleGroup.legMuscles)
                                }
                                PresetButton(title: "Full Body", isSelected: isFullBodySelected) {
                                    togglePreset([.fullBody])
                                }
                            }

                            // Individual muscle groups
                            FlowLayout(spacing: 8) {
                                ForEach(LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }) { muscle in
                                    WorkoutMuscleChip(
                                        muscle: muscle,
                                        isSelected: selectedMuscles.contains(muscle)
                                    ) {
                                        toggleMuscle(muscle)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let name = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = name.isEmpty ? defaultName : name
                        onStart(finalName, selectedType, Array(selectedMuscles))
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Presets

    private var isPushSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pushMuscles).isSubset(of: selectedMuscles)
    }

    private var isPullSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pullMuscles).isSubset(of: selectedMuscles)
    }

    private var isLegsSelected: Bool {
        Set(LiveWorkout.MuscleGroup.legMuscles).isSubset(of: selectedMuscles)
    }

    private var isFullBodySelected: Bool {
        selectedMuscles.contains(.fullBody)
    }

    private func togglePreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        let muscleSet = Set(muscles)
        if muscleSet.isSubset(of: selectedMuscles) {
            // Remove preset
            selectedMuscles.subtract(muscleSet)
        } else {
            // Add preset (and remove fullBody if adding specific muscles)
            selectedMuscles.formUnion(muscleSet)
            if muscles != [.fullBody] {
                selectedMuscles.remove(.fullBody)
            }
        }
        HapticManager.lightTap()
    }

    private func toggleMuscle(_ muscle: LiveWorkout.MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
            // Remove fullBody if adding specific muscles
            if muscle != .fullBody {
                selectedMuscles.remove(.fullBody)
            }
        }
        HapticManager.selectionChanged()
    }
}

// MARK: - Workout Type Button

private struct WorkoutTypeButton: View {
    let type: LiveWorkout.WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.title2)
                Text(type.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Muscle Chip

private struct WorkoutMuscleChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: muscle.iconName)
                    .font(.caption)
                Text(muscle.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    CustomWorkoutSetupSheet { name, type, muscles in
        print("Starting: \(name), \(type), \(muscles)")
    }
}
