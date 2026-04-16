//
//  CustomWorkoutSetupSheet.swift
//  Trai
//
//  Sheet for setting up a custom workout with optional workout type and target muscles
//

import SwiftUI

// MARK: - Custom Workout Setup Sheet

struct CustomWorkoutSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (String, LiveWorkout.WorkoutType, [LiveWorkout.MuscleGroup]) -> Void
    var orderedWorkoutTypes: [LiveWorkout.WorkoutType] = LiveWorkout.WorkoutType.allCases

    @State private var workoutName = ""
    @State private var selectedType: LiveWorkout.WorkoutType = .strength
    @State private var selectedMuscles: Set<LiveWorkout.MuscleGroup> = []

    private var defaultName: String {
        if selectedType.supportsMuscleTargets, !selectedMuscles.isEmpty {
            let muscleNames = selectedMuscles.sorted { $0.displayName < $1.displayName }
                .prefix(3)
                .map { $0.displayName }
                .joined(separator: " + ")
            return muscleNames
        }

        if selectedType == .custom {
            return "Custom Workout"
        }

        return "\(selectedType.displayName) Workout"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    nameCard

                    workoutTypeCard

                    if selectedType.supportsMuscleTargets {
                        targetMusclesCard
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", systemImage: "checkmark") {
                        let name = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = name.isEmpty ? defaultName : name
                        let muscles = selectedType.supportsMuscleTargets ? Array(selectedMuscles) : []
                        onStart(finalName, selectedType, muscles)
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .traiSheetBranding()
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workout Name", systemImage: "textformat")
                .font(.traiHeadline())

            TextField("e.g. Bouldering, Morning Flow, Long Run", text: $workoutName)
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .traiCard(cornerRadius: 16)
    }

    private var workoutTypeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workout Type", systemImage: "square.grid.2x2.fill")
                .font(.traiHeadline())

            Text("Pick the closest fit for this session.")
                .font(.traiLabel(12))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(orderedWorkoutTypes) { type in
                    WorkoutTypeButton(
                        type: type,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                        HapticManager.selectionChanged()
                    }
                }
            }
        }
        .traiCard(cornerRadius: 16)
    }

    private var targetMusclesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Target Areas", systemImage: "figure.strengthtraining.traditional")
                .font(.traiHeadline())

            Text("Optional for strength workouts")
                .font(.traiLabel(12))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
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

            if !selectedMuscles.isEmpty {
                Text("\(selectedMuscles.count) selected")
                    .font(.traiLabel(12))
                    .foregroundStyle(.secondary)
            }
        }
        .traiCard(cornerRadius: 16)
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
            selectedMuscles.subtract(muscleSet)
        } else {
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
        if isSelected {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fillOpacity: 0.18))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiTertiary(color: .secondary, size: .compact))
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: type.iconName)
                .font(.traiLabel(12))
            Text(type.displayName)
                .font(.traiLabel(12))
        }
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Text(title)
                    .font(.traiLabel(12))
            }
            .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fillOpacity: 0.18))
        } else {
            Button(action: action) {
                Text(title)
                    .font(.traiLabel(12))
            }
            .buttonStyle(.traiTertiary(color: .secondary, size: .compact))
        }
    }
}

// MARK: - Workout Muscle Chip

private struct WorkoutMuscleChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiSecondary(color: .accentColor, size: .compact, fillOpacity: 0.18))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.traiTertiary(color: .secondary, size: .compact))
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: muscle.iconName)
                .font(.traiLabel(12))
            Text(muscle.displayName)
                .font(.traiLabel(12))
        }
    }
}

// MARK: - Preview

#Preview {
    CustomWorkoutSetupSheet { name, type, muscles in
        print("Starting: \(name), \(type), \(muscles)")
    }
}
