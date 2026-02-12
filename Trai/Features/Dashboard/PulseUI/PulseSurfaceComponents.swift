//
//  PulseSurfaceComponents.swift
//  Trai
//
//  Reusable building blocks for the Dashboard Pulse surface.
//

import SwiftUI

struct PulseHeaderRow: View {
    let phase: DailyCoachRecommendation.Phase
    let onTune: () -> Void

    private var statusText: String {
        switch phase {
        case .morningPlan: "Planning"
        case .onTrack: "In Rhythm"
        case .atRisk: "Needs Attention"
        case .rescue: "Adaptive"
        case .completed: "Recovered"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TraiLensIcon(size: 20, palette: .energy)

            Text("Trai Pulse")
                .font(.headline)
                .fontWeight(.semibold)

            Circle()
                .fill(PulseTheme.phaseTint(phase))
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onTune) {
                Image(systemName: "slider.horizontal.3")
                    .font(.callout)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(.circle)
            }
            .buttonStyle(.plain)
        }
    }
}

struct PulseCoachMessageView: View {
    let title: String
    let message: String
    let phase: DailyCoachRecommendation.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PulseTheme.phaseTint(phase))

            Text(message)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}

struct PulseWhisperLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct PulseSavedResponseView: View {
    let text: String
    let style: TraiPulseSurfaceType
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PulseTheme.surfaceTint(style))
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Edit Response", action: onEdit)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(PulseTheme.surfaceTint(style))
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct PulseChoiceChip: View {
    let title: String
    let isSelected: Bool
    let emphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PulseTheme.chipPaddingH)
                .padding(.vertical, PulseTheme.chipPaddingV)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : (emphasized ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected || emphasized ? Color.accentColor : Color.primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

struct PulsePlanProposalView: View {
    let proposal: TraiPulsePlanProposal
    let onApply: () -> Void
    let onReview: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proposal.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)

            Text(proposal.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !proposal.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(proposal.changes, id: \.self) { change in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.8))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(change)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text(proposal.impact)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(proposal.applyLabel, action: onApply)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                Button(proposal.reviewLabel, action: onReview)
                    .buttonStyle(.bordered)
                    .tint(.accentColor)

                Button(proposal.deferLabel, action: onLater)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PulseTextComposer: View {
    let placeholder: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let submitTitle: String
    let bordered: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }

            if bordered {
                Button(submitTitle, action: onSubmit)
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button(submitTitle, action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct PulseActionButtonsRow: View {
    let primaryTitle: String
    let secondaryTitle: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Button(action: onSecondary) {
                Text(secondaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }
}
