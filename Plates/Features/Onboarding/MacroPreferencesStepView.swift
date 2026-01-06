//
//  MacroPreferencesStepView.swift
//  Plates
//
//  Onboarding step for selecting which macros to track
//

import SwiftUI

struct MacroPreferencesStepView: View {
    @Binding var enabledMacros: Set<MacroType>

    @State private var headerVisible = false
    @State private var macrosVisible = false
    @State private var previewVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                    .padding(.top, 16)

                macrosSection
                    .offset(y: macrosVisible ? 0 : 30)
                    .opacity(macrosVisible ? 1 : 0)

                previewSection
                    .offset(y: previewVisible ? 0 : 30)
                    .opacity(previewVisible ? 1 : 0)
                    .padding(.bottom, 140)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startEntranceAnimations()
        }
    }

    private func startEntranceAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
            macrosVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.3)) {
            previewVisible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 2)
                    .frame(width: 95, height: 95)
                    .scaleEffect(headerVisible ? 1 : 0.5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(headerVisible ? 1 : 0.8)

            Text("Track What Matters")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Choose which nutrients to monitor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    // MARK: - Macros Section

    private var macrosSection: some View {
        VStack(spacing: 12) {
            ForEach(MacroType.displayOrder) { macro in
                MacroToggleCard(
                    macro: macro,
                    isEnabled: enabledMacros.contains(macro)
                ) {
                    HapticManager.lightTap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        if enabledMacros.contains(macro) {
                            enabledMacros.remove(macro)
                        } else {
                            enabledMacros.insert(macro)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(spacing: 12) {
            Text("Your Dashboard Preview")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            MacroRingsPreview(enabledMacros: enabledMacros)
        }
    }
}

// MARK: - Macro Toggle Card

private struct MacroToggleCard: View {
    let macro: MacroType
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if isEnabled {
                        Circle()
                            .fill(macro.color.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .blur(radius: 6)
                    }

                    Circle()
                        .fill(
                            isEnabled
                                ? LinearGradient(
                                    colors: [macro.color, macro.color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [macro.color.opacity(0.15), macro.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: macro.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isEnabled ? .white : macro.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(macro.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isEnabled ? macro.color : Color(.tertiaryLabel))
                    .symbolEffect(.bounce, value: isEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isEnabled ? macro.color.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEnabled)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
        }
    }
}

// MARK: - Macro Rings Preview

private struct MacroRingsPreview: View {
    let enabledMacros: Set<MacroType>

    private var orderedMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            if orderedMacros.isEmpty {
                emptyState
            } else {
                HStack(spacing: 16) {
                    ForEach(orderedMacros) { macro in
                        PreviewRingItem(macro: macro)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.title)
                .foregroundStyle(.tertiary)

            Text("Calories Only")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("You'll only see total calories")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Preview Ring Item

private struct PreviewRingItem: View {
    let macro: MacroType

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 6)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        macro.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Text(macro.shortName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(macro.color)
            }

            Text(macro.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MacroPreferencesStepView(
        enabledMacros: .constant(MacroType.defaultEnabled)
    )
}
