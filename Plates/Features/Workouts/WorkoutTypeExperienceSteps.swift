//
//  WorkoutTypeExperienceSteps.swift
//  Plates
//
//  Workout type and experience level step views for workout plan setup
//

import SwiftUI

// MARK: - Workout Type Step

struct WorkoutTypeStepView: View {
    @Binding var selection: Set<WorkoutPlanGenerationRequest.WorkoutType>
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

                        Image(systemName: "figure.mixed.cardio")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What kind of training?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Select all that interest you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.WorkoutType.allCases.filter { $0 != .mixed }) { type in
                        WorkoutTypeOptionCard(
                            type: type,
                            isSelected: selection.contains(type)
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selection.contains(type) {
                                    selection.remove(type)
                                } else {
                                    selection.insert(type)
                                    // Clear custom if selecting predefined
                                    if !customText.isEmpty {
                                        customText = ""
                                        showingCustomInput = false
                                    }
                                }
                            }
                        }
                    }

                    // Other/Custom option - full width
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your training style...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        // Clear predefined selections when using custom
                        if !selection.isEmpty {
                            selection.removeAll()
                        }
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
            // If custom text exists, show the input
            if !customText.isEmpty {
                showingCustomInput = true
            }
        }
    }
}

private struct WorkoutTypeOptionCard: View {
    let type: WorkoutPlanGenerationRequest.WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(type.description)
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

// MARK: - Experience Step

struct ExperienceStepView: View {
    @Binding var selection: WorkoutPlanGenerationRequest.ExperienceLevel?
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

                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("Your experience level?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("This helps us tailor your plan")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.ExperienceLevel.allCases) { level in
                        ExperienceOptionCard(
                            level: level,
                            isSelected: selection == level && customText.isEmpty
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = level
                                customText = ""
                                showingCustomInput = false
                            }
                        }
                    }

                    // Custom option
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your experience level...",
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

private struct ExperienceOptionCard: View {
    let level: WorkoutPlanGenerationRequest.ExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: level.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .leading)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .frame(minHeight: 76)
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

// MARK: - Previews

#Preview("Workout Type") {
    WorkoutTypeStepView(selection: .constant([]), customText: .constant(""))
}

#Preview("Experience") {
    ExperienceStepView(selection: .constant(nil), customText: .constant(""))
}
