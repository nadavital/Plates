//
//  FoodCameraNoCameraFallbackView.swift
//  Trai
//
//  Fallback capture screen used when camera access is unavailable.
//

import SwiftUI
import PhotosUI

struct FoodCameraNoCameraFallbackView: View {
    @Binding var description: String
    let suggestions: [FoodSuggestion]
    let onSelectSuggestion: (FoodSuggestion) -> Void
    let onManualEntry: () -> Void
    let onSubmitDescription: () -> Void
    let onEnableCamera: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    @FocusState private var isDescriptionFocused: Bool

    private var canSubmitDescription: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TraiSpacing.md) {
                statusRow

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: TraiSpacing.sm) {
                        TraiSectionHeader("Quick picks", icon: "clock.arrow.circlepath")

                        FoodCameraSuggestionRail(
                            suggestions: suggestions,
                            onSelectSuggestion: onSelectSuggestion
                        )
                        .padding(.horizontal, -TraiSpacing.md)
                    }
                    .traiCard(cornerRadius: TraiRadius.medium)
                }

                VStack(alignment: .leading, spacing: TraiSpacing.sm) {
                    TraiSectionHeader("Describe it", icon: "text.alignleft")

                    TextField("Describe your meal for AI analysis...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(
                            Color(.tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .focused($isDescriptionFocused)
                        .submitLabel(.done)
                        .onSubmit(submitDescription)

                    Button {
                        submitDescription()
                    } label: {
                        Label("Analyze Description", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiPrimary(fullWidth: true))
                    .disabled(!canSubmitDescription)
                }
                .traiCard(cornerRadius: TraiRadius.medium)

                VStack(alignment: .leading, spacing: TraiSpacing.sm) {
                    TraiSectionHeader("Other ways to log", icon: "ellipsis.circle")

                    HStack(spacing: TraiSpacing.sm) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            FoodCameraCompactActionLabel(
                                title: "Library",
                                systemImage: "photo.on.rectangle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.traiSecondary(color: .accentColor, fullWidth: true, height: 44))

                        Button(action: onManualEntry) {
                            FoodCameraCompactActionLabel(
                                title: "Manual",
                                systemImage: "square.and.pencil"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.traiTertiary(fullWidth: true, height: 44))
                        .accessibilityIdentifier("foodCameraManualButton")
                    }
                }
                .traiCard(cornerRadius: TraiRadius.medium)
            }
            .padding(.horizontal, TraiSpacing.md)
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .traiBackground(intensity: 0.8)
        .accessibilityIdentifier("foodCameraNoCameraFallback")
    }

    private var statusRow: some View {
        HStack(spacing: TraiSpacing.sm) {
            Image(systemName: "camera.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TraiColors.brandAccent)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(TraiGradient.cardSurface(TraiColors.brandAccent))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Camera off")
                    .font(.traiHeadline(16))

                Text("Use text, your library, or manual entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onEnableCamera) {
                Label("Enable", systemImage: "camera.fill")
            }
            .buttonStyle(.traiTertiary(color: .accentColor, size: .compact, width: 96, height: 36))
        }
        .traiCard(cornerRadius: TraiRadius.medium, contentPadding: 14)
    }
 
    private func submitDescription() {
        guard canSubmitDescription else { return }
        isDescriptionFocused = false
        onSubmitDescription()
    }
}

private struct FoodCameraCompactActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.traiLabel(14))
            .lineLimit(1)
    }
}
