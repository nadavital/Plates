//
//  MacroTrackingSettingsSheet.swift
//  Trai
//
//  Settings sheet for configuring which macros to track
//

import SwiftUI

struct MacroTrackingSettingsSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var localEnabledMacros: Set<MacroType>

    init(profile: UserProfile) {
        self.profile = profile
        _localEnabledMacros = State(initialValue: profile.enabledMacros)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MacroType.displayOrder) { macro in
                        MacroToggleRow(
                            macro: macro,
                            isEnabled: localEnabledMacros.contains(macro)
                        ) {
                            HapticManager.lightTap()
                            if localEnabledMacros.contains(macro) {
                                localEnabledMacros.remove(macro)
                            } else {
                                localEnabledMacros.insert(macro)
                            }
                        }
                    }
                } header: {
                    Text("Tracked Macros")
                } footer: {
                    Text("Choose which nutrients to display across the app. You can track just calories by disabling all macros.")
                }

                Section {
                    MacroPreviewCard(enabledMacros: localEnabledMacros)
                } header: {
                    Text("Preview")
                }

                Section {
                    Button("Reset to Defaults") {
                        HapticManager.lightTap()
                        withAnimation {
                            localEnabledMacros = MacroType.defaultEnabled
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Macro Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        profile.enabledMacros = localEnabledMacros
                        HapticManager.success()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Macro Toggle Row

private struct MacroToggleRow: View {
    let macro: MacroType
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        isEnabled
                            ? macro.color
                            : macro.color.opacity(0.2)
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: macro.iconName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isEnabled ? .white : macro.color)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(macro.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled ? macro.color : Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isEnabled)
    }
}

// MARK: - Macro Preview Card

private struct MacroPreviewCard: View {
    let enabledMacros: Set<MacroType>

    private var orderedMacros: [MacroType] {
        MacroType.displayOrder.filter { enabledMacros.contains($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            if orderedMacros.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.title2)
                        .foregroundStyle(.tertiary)

                    Text("Calories Only")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Only total calories will be displayed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 16)
            } else {
                HStack(spacing: 12) {
                    ForEach(orderedMacros) { macro in
                        PreviewRing(macro: macro)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview Ring

private struct PreviewRing: View {
    let macro: MacroType

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(macro.color.opacity(0.2), lineWidth: 4)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(
                        macro.color,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Text(macro.shortName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(macro.color)
            }

            Text(macro.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MacroTrackingSettingsSheet(profile: UserProfile())
}
