//
//  ProfileEditComponents.swift
//  Plates
//
//  Components for profile editing
//

import SwiftUI

// MARK: - Activity Level Option

struct ActivityLevelOption: View {
    let level: UserProfile.ActivityLevel
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    private var iconForLevel: String {
        switch level {
        case .sedentary: "figure.seated.seatbelt"
        case .light: "figure.walk"
        case .moderate: "figure.run"
        case .active: "figure.highintensity.intervaltraining"
        case .veryActive: "figure.strengthtraining.traditional"
        }
    }

    private var colorForLevel: Color {
        switch level {
        case .sedentary: .gray
        case .light: .blue
        case .moderate: .green
        case .active: .orange
        case .veryActive: .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Intensity bars
                HStack(spacing: 2) {
                    ForEach(0..<5) { barIndex in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barIndex <= index ? colorForLevel : Color(.tertiarySystemBackground))
                            .frame(width: 4, height: 16)
                    }
                }
                .frame(width: 28)

                // Icon
                Circle()
                    .fill(isSelected ? colorForLevel : Color(.tertiarySystemBackground))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: iconForLevel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(level.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colorForLevel)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? colorForLevel.opacity(0.5) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
