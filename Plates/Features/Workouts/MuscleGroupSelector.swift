//
//  MuscleGroupSelector.swift
//  Plates
//
//  Inline muscle group selection component for workouts
//

import SwiftUI

// MARK: - Muscle Group Selector

struct MuscleGroupSelector: View {
    @Binding var selectedMuscles: Set<LiveWorkout.MuscleGroup>
    let isCustomWorkout: Bool

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - tap to expand if custom workout
            Button {
                if isCustomWorkout || selectedMuscles.isEmpty {
                    withAnimation(.snappy) { isExpanded.toggle() }
                    HapticManager.lightTap()
                }
            } label: {
                HStack {
                    if selectedMuscles.isEmpty {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.accent)
                        Text("Select target muscles")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.accent)
                        Text("Targeting")
                            .foregroundStyle(.secondary)

                        // Show selected muscles as chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(selectedMuscles).sorted { $0.displayName < $1.displayName }) { muscle in
                                    Text(muscle.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(.capsule)
                                }
                            }
                        }
                    }

                    Spacer()

                    if isCustomWorkout || selectedMuscles.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)

            // Expanded selection
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Quick presets
                    HStack(spacing: 8) {
                        PresetChip(title: "Push", isSelected: isPushSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.pushMuscles)
                        }
                        PresetChip(title: "Pull", isSelected: isPullSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.pullMuscles)
                        }
                        PresetChip(title: "Legs", isSelected: isLegsSelected) {
                            togglePreset(LiveWorkout.MuscleGroup.legMuscles)
                        }
                    }

                    // Individual muscles
                    FlowLayout(spacing: 8) {
                        ForEach(LiveWorkout.MuscleGroup.allCases.filter { $0 != .fullBody }) { muscle in
                            MuscleSelectChip(
                                muscle: muscle,
                                isSelected: selectedMuscles.contains(muscle)
                            ) {
                                toggleMuscle(muscle)
                            }
                        }
                    }

                    // Done button
                    Button {
                        withAnimation(.snappy) { isExpanded = false }
                    } label: {
                        Text("Done")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .onAppear {
            // Auto-expand for custom workouts with no muscles selected
            if isCustomWorkout && selectedMuscles.isEmpty {
                isExpanded = true
            }
        }
    }

    private var isPushSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pushMuscles).isSubset(of: selectedMuscles)
    }

    private var isPullSelected: Bool {
        Set(LiveWorkout.MuscleGroup.pullMuscles).isSubset(of: selectedMuscles)
    }

    private var isLegsSelected: Bool {
        Set(LiveWorkout.MuscleGroup.legMuscles).isSubset(of: selectedMuscles)
    }

    private func togglePreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        let muscleSet = Set(muscles)
        if muscleSet.isSubset(of: selectedMuscles) {
            selectedMuscles.subtract(muscleSet)
        } else {
            selectedMuscles.formUnion(muscleSet)
        }
        HapticManager.lightTap()
    }

    private func toggleMuscle(_ muscle: LiveWorkout.MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
        HapticManager.selectionChanged()
    }
}

// MARK: - Preset Chip

private struct PresetChip: View {
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

// MARK: - Muscle Select Chip

private struct MuscleSelectChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: muscle.iconName)
                    .font(.caption2)
                Text(muscle.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
