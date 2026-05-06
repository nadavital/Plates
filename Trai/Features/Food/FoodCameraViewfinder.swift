//
//  FoodCameraViewfinder.swift
//  Trai
//
//  Camera viewfinder overlay with capture controls
//

import SwiftUI
import PhotosUI

struct FoodCameraViewfinder: View {
    let cameraService: CameraService
    let isCapturingPhoto: Bool
    @Binding var description: String
    let suggestions: [FoodSuggestion]
    let onCapture: () -> Void
    let onSelectSuggestion: (FoodSuggestion) -> Void
    let onManualEntry: () -> Void
    let onSubmitDescription: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    @FocusState private var isDescriptionFocused: Bool

    private var canSubmitDescription: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

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

                if !suggestions.isEmpty {
                    FoodCameraSuggestionRail(
                        suggestions: suggestions,
                        onSelectSuggestion: onSelectSuggestion,
                        onDismissKeyboard: {
                            isDescriptionFocused = false
                        }
                    )
                    .padding(.bottom, 12)
                }

                FoodCameraDescriptionBar(
                    description: $description,
                    isDescriptionFocused: $isDescriptionFocused,
                    canSubmitDescription: canSubmitDescription,
                    onSubmitDescription: onSubmitDescription
                )
                .padding(.horizontal)

                FoodCameraControlBar(
                    isCapturingPhoto: isCapturingPhoto,
                    onCapture: onCapture,
                    onManualEntry: onManualEntry,
                    selectedPhotoItem: $selectedPhotoItem
                )
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

struct FoodCameraSuggestionRail: View {
    let suggestions: [FoodSuggestion]
    let onSelectSuggestion: (FoodSuggestion) -> Void
    let onDismissKeyboard: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { suggestion in
                        FoodCameraSuggestionChip(suggestion: suggestion) {
                            onSelectSuggestion(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        onDismissKeyboard()
                    }
                )
            }
        }
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture().onEnded {
                onDismissKeyboard()
            }
        )
        .scrollClipDisabled()
        .padding(.horizontal)
    }
}

private struct FoodCameraDescriptionBar: View {
    @Binding var description: String
    @FocusState.Binding var isDescriptionFocused: Bool
    let canSubmitDescription: Bool
    let onSubmitDescription: () -> Void

    @State private var inputBarHeight: CGFloat = 52

    private var inputCornerRadius: CGFloat {
        min(inputBarHeight / 2, 26)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                TextField("Describe your food...", text: $description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isDescriptionFocused)
                    .accessibilityIdentifier("foodCameraDescriptionField")
                    .onSubmit {
                        if canSubmitDescription {
                            saveDescription()
                        }
                    }

                Button {
                    saveDescription()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .glassEffect(.regular.tint(canSubmitDescription ? .accent : .gray).interactive(), in: .circle)
                .opacity(canSubmitDescription ? 1 : 0.5)
                .disabled(!canSubmitDescription)
                .accessibilityLabel("Save description")
                .accessibilityIdentifier("foodCameraDescriptionSubmitButton")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(
                .regular
                    .tint(Color.white.opacity(0.08))
                    .interactive(),
                in: .rect(cornerRadius: inputCornerRadius)
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { _, newHeight in
                inputBarHeight = newHeight
            }
            .animation(.snappy(duration: 0.18), value: inputCornerRadius)
        }
    }

    private func saveDescription() {
        guard canSubmitDescription else { return }
        isDescriptionFocused = false
        onSubmitDescription()
    }
}

private struct FoodCameraControlBar: View {
    let isCapturingPhoto: Bool
    let onCapture: () -> Void
    let onManualEntry: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 24) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    FoodCameraAccessoryButtonLabel(systemName: "photo.on.rectangle", title: "Library")
                }
                .buttonStyle(.glass)

                Button(action: onCapture) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 56, height: 56)

                        if isCapturingPhoto {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: 74, height: 74)
                    }
                }
                .disabled(isCapturingPhoto)
                .opacity(isCapturingPhoto ? 0.6 : 1)

                Button(action: onManualEntry) {
                    FoodCameraAccessoryButtonLabel(systemName: "square.and.pencil", title: "Manual")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("foodCameraManualButton")
            }
        }
    }
}

struct FoodCameraAccessoryButtonLabel: View {
    let systemName: String
    let title: String
    var foregroundStyle: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.title3)
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(foregroundStyle)
        .frame(width: 70, height: 58)
    }
}

struct FoodCameraSuggestionChip: View {
    let suggestion: FoodSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(suggestion.emoji)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.title)
                            .font(.traiHeadline(15))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TraiColors.brandAccent)
                }

                Spacer(minLength: 0)

                Text(suggestion.detail)
                    .font(.traiLabel(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 220, alignment: .leading)
            .frame(height: 108, alignment: .topLeading)
            .glassEffect(
                .regular.interactive(),
                in: .rect(cornerRadius: 22)
            )
        }
        .buttonStyle(.plain)
    }
}
