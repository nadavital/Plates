//
//  CardioExerciseCard.swift
//  Plates
//
//  Cardio exercise card component for live workout tracking
//

import SwiftUI

// MARK: - Cardio Exercise Card

struct CardioExerciseCard: View {
    let entry: LiveWorkoutEntry
    let onUpdateDuration: (Int) -> Void
    let onUpdateDistance: (Double) -> Void
    let onComplete: () -> Void
    var onDeleteExercise: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false
    @State private var durationMinutes: String = ""
    @State private var durationSeconds: String = ""
    @State private var distanceKm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                                Text(entry.exerciseName)
                                    .font(.headline)
                            }

                            if entry.completedAt != nil {
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if onDeleteExercise != nil {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove Exercise", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }

            // Cardio inputs
            if isExpanded {
                VStack(spacing: 16) {
                    // Duration input
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text("Duration")
                            .font(.subheadline)

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("00", text: $durationMinutes)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 40)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: durationMinutes) { _, _ in
                                    updateDuration()
                                }

                            Text(":")
                                .foregroundStyle(.secondary)

                            TextField("00", text: $durationSeconds)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 40)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: durationSeconds) { _, _ in
                                    updateDuration()
                                }
                        }
                    }

                    // Distance input
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text("Distance")
                            .font(.subheadline)

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("0.00", text: $distanceKm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(.rect(cornerRadius: 6))
                                .onChange(of: distanceKm) { _, newValue in
                                    if let km = Double(newValue) {
                                        onUpdateDistance(km * 1000) // Convert to meters
                                    }
                                }

                            Text("km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Complete button
                    Button(action: onComplete) {
                        HStack {
                            Image(systemName: entry.completedAt != nil ? "checkmark.circle.fill" : "circle")
                            Text(entry.completedAt != nil ? "Completed" : "Mark Complete")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(entry.completedAt != nil ? .green : .accent)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .onAppear {
            // Load existing values
            if let seconds = entry.durationSeconds {
                durationMinutes = "\(seconds / 60)"
                durationSeconds = String(format: "%02d", seconds % 60)
            }
            if let meters = entry.distanceMeters {
                distanceKm = String(format: "%.2f", meters / 1000)
            }
        }
        .confirmationDialog(
            "Remove \(entry.exerciseName)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                onDeleteExercise?()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func updateDuration() {
        let mins = Int(durationMinutes) ?? 0
        let secs = Int(durationSeconds) ?? 0
        onUpdateDuration(mins * 60 + secs)
    }
}
