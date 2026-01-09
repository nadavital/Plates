//
//  WorkoutSummarySheet.swift
//  Plates
//
//  Workout completion summary sheet
//

import SwiftUI

// MARK: - Workout Summary Sheet

struct WorkoutSummarySheet: View {
    let workout: LiveWorkout
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Workout Complete!")
                        .font(.title)
                        .bold()

                    // Stats
                    VStack(spacing: 16) {
                        SummaryStatRow(
                            label: "Duration",
                            value: workout.formattedDuration,
                            icon: "clock.fill"
                        )

                        SummaryStatRow(
                            label: "Exercises",
                            value: "\(workout.entries?.count ?? 0)",
                            icon: "dumbbell.fill"
                        )

                        SummaryStatRow(
                            label: "Total Sets",
                            value: "\(workout.totalSets)",
                            icon: "square.stack.3d.up.fill"
                        )

                        if workout.totalVolume > 0 {
                            SummaryStatRow(
                                label: "Total Volume",
                                value: "\(Int(workout.totalVolume)) kg",
                                icon: "scalemass.fill"
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    // Exercises completed
                    if let entries = workout.entries, !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises")
                                .font(.headline)

                            ForEach(entries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                                HStack {
                                    Text(entry.exerciseName)
                                    Spacer()
                                    Text("\(entry.completedSets?.count ?? 0) sets")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - Summary Stat Row

struct SummaryStatRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .bold()
        }
    }
}
