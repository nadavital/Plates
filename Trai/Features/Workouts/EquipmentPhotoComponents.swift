//
//  EquipmentPhotoComponents.swift
//  Trai
//
//  Camera and analysis components for identifying gym equipment
//

import SwiftUI

// MARK: - Equipment Camera View

struct EquipmentCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data) -> Void

    @State private var cameraService = CameraService()

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                CameraPreviewView(cameraService: cameraService)
                    .ignoresSafeArea()

                // Overlay UI
                VStack {
                    Spacer()

                    // Instructions
                    Text("Point at gym equipment")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(.bottom, 20)

                    // Capture button
                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .task {
                await cameraService.requestPermission()
            }
        }
    }

    private func capturePhoto() {
        Task {
            if let image = await cameraService.capturePhoto(),
               let imageData = image.jpegData(compressionQuality: 0.8) {
                onCapture(imageData)
            }
        }
    }
}

// MARK: - Equipment Analysis Sheet

struct EquipmentAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: ExercisePhotoAnalysis
    /// Callback with (exerciseName, muscleGroup, equipmentName)
    let onSelectExercise: (String, String, String?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Equipment info card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .foregroundStyle(.accent)

                            Text(analysis.equipmentName)
                                .font(.title2)
                                .bold()
                        }

                        Text(analysis.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        if let tips = analysis.tips {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.subheadline)

                                Text(tips)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 12))
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    // Suggested exercises
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercises You Can Do")
                            .font(.headline)

                        ForEach(analysis.suggestedExercises) { exercise in
                            Button {
                                onSelectExercise(exercise.name, exercise.muscleGroup, analysis.equipmentName)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.name)
                                            .font(.body)
                                            .fontWeight(.medium)

                                        HStack(spacing: 6) {
                                            Text(exercise.muscleGroup.capitalized)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Color.accent.opacity(0.2))
                                                .clipShape(.capsule)

                                            if let howTo = exercise.howTo {
                                                Text(howTo)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.accent)
                                }
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(.rect(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Equipment Identified")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
