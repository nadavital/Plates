//
//  MuscleRecoveryCard.swift
//  Plates
//
//  Displays muscle group recovery status with visual indicators
//

import SwiftUI

// MARK: - Muscle Recovery Card

struct MuscleRecoveryCard: View {
    let recoveryInfo: [MuscleRecoveryService.MuscleRecoveryInfo]
    var onTap: (() -> Void)?

    private var readyMuscles: [MuscleRecoveryService.MuscleRecoveryInfo] {
        recoveryInfo.filter { $0.status == .ready }
    }

    private var recoveringMuscles: [MuscleRecoveryService.MuscleRecoveryInfo] {
        recoveryInfo.filter { $0.status == .recovering }
    }

    private var tiredMuscles: [MuscleRecoveryService.MuscleRecoveryInfo] {
        recoveryInfo.filter { $0.status == .tired }
    }

    var body: some View {
        Button {
            onTap?()
            HapticManager.selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Label("Muscle Recovery", systemImage: "figure.strengthtraining.traditional")
                        .font(.headline)
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Muscle groups grid
                VStack(alignment: .leading, spacing: 12) {
                    if !readyMuscles.isEmpty {
                        MuscleStatusRow(
                            title: "Ready to train",
                            muscles: readyMuscles,
                            status: .ready
                        )
                    }

                    if !recoveringMuscles.isEmpty {
                        MuscleStatusRow(
                            title: "Recovering",
                            muscles: recoveringMuscles,
                            status: .recovering
                        )
                    }

                    if !tiredMuscles.isEmpty {
                        MuscleStatusRow(
                            title: "Needs rest",
                            muscles: tiredMuscles,
                            status: .tired
                        )
                    }

                    if recoveryInfo.isEmpty {
                        emptyStateView
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        HStack {
            Image(systemName: "dumbbell")
                .foregroundStyle(.secondary)
            Text("Start logging workouts to track recovery")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Muscle Status Row

struct MuscleStatusRow: View {
    let title: String
    let muscles: [MuscleRecoveryService.MuscleRecoveryInfo]
    let status: MuscleRecoveryService.RecoveryStatus

    private var statusColor: Color {
        switch status {
        case .ready: .green
        case .recovering: .orange
        case .tired: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(muscles) { muscle in
                    MuscleChip(muscle: muscle.muscleGroup, status: status)
                }
            }
        }
    }
}

// MARK: - Muscle Chip

struct MuscleChip: View {
    let muscle: LiveWorkout.MuscleGroup
    let status: MuscleRecoveryService.RecoveryStatus

    private var backgroundColor: Color {
        switch status {
        case .ready: Color.green.opacity(0.2)
        case .recovering: Color.orange.opacity(0.2)
        case .tired: Color.red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .ready: .green
        case .recovering: .orange
        case .tired: .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: muscle.iconName)
                .font(.caption2)
            Text(muscle.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(.capsule)
    }
}

// MARK: - Muscle Recovery Detail Sheet

struct MuscleRecoveryDetailSheet: View {
    let recoveryInfo: [MuscleRecoveryService.MuscleRecoveryInfo]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleRecoveryService.RecoveryStatus.allCases, id: \.rawValue) { status in
                    let muscles = recoveryInfo.filter { $0.status == status }
                    if !muscles.isEmpty {
                        Section {
                            ForEach(muscles) { muscle in
                                MuscleRecoveryRow(info: muscle)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: status.iconName)
                                Text(status.displayName)
                            }
                            .foregroundStyle(colorForStatus(status))
                        }
                    }
                }
            }
            .navigationTitle("Muscle Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func colorForStatus(_ status: MuscleRecoveryService.RecoveryStatus) -> Color {
        switch status {
        case .ready: .green
        case .recovering: .orange
        case .tired: .red
        }
    }
}

// MARK: - Muscle Recovery Row

struct MuscleRecoveryRow: View {
    let info: MuscleRecoveryService.MuscleRecoveryInfo

    private var statusColor: Color {
        switch info.status {
        case .ready: .green
        case .recovering: .orange
        case .tired: .red
        }
    }

    var body: some View {
        HStack {
            Image(systemName: info.muscleGroup.iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.muscleGroup.displayName)
                    .font(.body)

                Text(info.formattedLastTrained)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(info.status.displayName)
                .font(.caption)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .clipShape(.capsule)
        }
    }
}

// MARK: - Preview

#Preview {
    MuscleRecoveryCard(recoveryInfo: [
        MuscleRecoveryService.MuscleRecoveryInfo(
            muscleGroup: .chest,
            status: .ready,
            lastTrainedAt: Date().addingTimeInterval(-72 * 3600),
            hoursSinceTraining: 72
        ),
        MuscleRecoveryService.MuscleRecoveryInfo(
            muscleGroup: .back,
            status: .ready,
            lastTrainedAt: Date().addingTimeInterval(-60 * 3600),
            hoursSinceTraining: 60
        ),
        MuscleRecoveryService.MuscleRecoveryInfo(
            muscleGroup: .shoulders,
            status: .recovering,
            lastTrainedAt: Date().addingTimeInterval(-30 * 3600),
            hoursSinceTraining: 30
        ),
        MuscleRecoveryService.MuscleRecoveryInfo(
            muscleGroup: .biceps,
            status: .tired,
            lastTrainedAt: Date().addingTimeInterval(-12 * 3600),
            hoursSinceTraining: 12
        )
    ])
    .padding()
}
