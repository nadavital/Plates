//
//  BiometricsComponents.swift
//  Plates
//
//  Reusable components for biometrics input
//

import SwiftUI

// MARK: - Gender Selection Button

struct GenderSelectionButton: View {
    let gender: UserProfile.Gender
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            HapticManager.cardSelected()
            action()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 64, height: 64)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color(.tertiarySystemBackground), Color(.tertiarySystemBackground)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(
                            color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                            radius: 8,
                            y: 4
                        )

                    Image(systemName: iconName)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .scaleEffect(isSelected ? 1.1 : 1)
                }

                Text(gender.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
        }
    }

    private var iconName: String {
        switch gender {
        case .male: "figure.stand"
        case .female: "figure.stand.dress"
        case .notSpecified: "person.fill.questionmark"
        }
    }
}

// MARK: - Press Events Modifier

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

// MARK: - Unit Toggle

struct UnitToggle: View {
    @Binding var usesMetric: Bool
    let metricLabel: String
    let imperialLabel: String

    var body: some View {
        HStack(spacing: 0) {
            toggleButton(label: imperialLabel, isSelected: !usesMetric) {
                if usesMetric {
                    HapticManager.toggleSwitched()
                    usesMetric = false
                }
            }
            toggleButton(label: metricLabel, isSelected: usesMetric) {
                if !usesMetric {
                    HapticManager.toggleSwitched()
                    usesMetric = true
                }
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.capsule)
    }

    private func toggleButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.clear)
                )
                .foregroundStyle(isSelected ? .white : .secondary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Measurement Input

struct MeasurementInput: View {
    let placeholder: String
    @Binding var value: String
    let unit: String
    var onFocus: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $value)
                .keyboardType(.decimalPad)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                )
                .focused($isFocused)
                .onChange(of: isFocused, initial: false) { _, focused in
                    if focused {
                        HapticManager.lightTap()
                        onFocus?()
                    }
                }

            Text(unit)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 32)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
