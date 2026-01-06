//
//  FoodCameraViewfinder.swift
//  Plates
//
//  Camera viewfinder overlay with capture controls
//

import SwiftUI
import PhotosUI

struct FoodCameraViewfinder: View {
    let cameraService: CameraService
    @Binding var description: String
    let onCapture: () -> Void
    let onManualEntry: () -> Void
    let onSubmitDescription: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    @FocusState private var isDescriptionFocused: Bool

    private var canSubmitDescription: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraService: cameraService)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture {
                    isDescriptionFocused = false
                }

            // Overlay gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            // Controls overlay
            VStack {
                Spacer()
                    .contentShape(.rect)
                    .onTapGesture {
                        isDescriptionFocused = false
                    }

                // Description input with send button
                HStack(spacing: 10) {
                    TextField("Describe your food...", text: $description)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                        .focused($isDescriptionFocused)
                        .onSubmit {
                            if canSubmitDescription {
                                onSubmitDescription()
                            }
                        }

                    if isDescriptionFocused {
                        if canSubmitDescription {
                            Button {
                                isDescriptionFocused = false
                                onSubmitDescription()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Button("Done") {
                                isDescriptionFocused = false
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)

                // Capture controls
                HStack(spacing: 32) {
                    // Photo library
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Library")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                    }

                    // Capture button
                    Button(action: onCapture) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }

                    // Manual entry
                    Button(action: onManualEntry) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                            Text("Manual")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }
}
