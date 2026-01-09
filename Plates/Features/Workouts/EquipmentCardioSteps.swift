//
//  EquipmentCardioSteps.swift
//  Plates
//
//  Equipment and cardio step views for workout plan setup
//

import SwiftUI

// MARK: - Equipment Step

struct EquipmentStepView: View {
    @Binding var selection: WorkoutPlanGenerationRequest.EquipmentAccess?
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What equipment?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("We'll pick exercises that work for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.EquipmentAccess.allCases) { equipment in
                        EquipmentOptionCard(
                            equipment: equipment,
                            isSelected: selection == equipment && customText.isEmpty
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = equipment
                                customText = ""
                                showingCustomInput = false
                            }
                        }
                    }

                    // Custom option
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your equipment setup...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        selection = nil
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct EquipmentOptionCard: View {
    let equipment: WorkoutPlanGenerationRequest.EquipmentAccess
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: equipment.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(equipment.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(equipment.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cardio Step

struct CardioStepView: View {
    @Binding var selection: Set<WorkoutPlanGenerationRequest.CardioType>
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    /// Cardio types excluding anyCardio (replaced with custom)
    private var cardioOptions: [WorkoutPlanGenerationRequest.CardioType] {
        WorkoutPlanGenerationRequest.CardioType.allCases.filter { $0 != .anyCardio }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What cardio do you enjoy?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Select all that apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options in grid (even number for clean layout)
                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cardioOptions) { cardio in
                            CardioOptionCard(
                                cardio: cardio,
                                isSelected: selection.contains(cardio) && customText.isEmpty
                            ) {
                                HapticManager.lightTap()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selection.contains(cardio) {
                                        selection.remove(cardio)
                                    } else {
                                        selection.insert(cardio)
                                        // Clear custom when selecting predefined
                                        customText = ""
                                        showingCustomInput = false
                                    }
                                }
                            }
                        }
                    }

                    // Custom option - full width
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your preferred cardio...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        selection.removeAll()
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct CardioOptionCard: View {
    let cardio: WorkoutPlanGenerationRequest.CardioType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: cardio.iconName)
                    .font(.title)
                    .foregroundStyle(isSelected ? .accent : .secondary)

                Text(cardio.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Equipment") {
    EquipmentStepView(selection: .constant(nil), customText: .constant(""))
}

#Preview("Cardio") {
    CardioStepView(selection: .constant([]), customText: .constant(""))
}
