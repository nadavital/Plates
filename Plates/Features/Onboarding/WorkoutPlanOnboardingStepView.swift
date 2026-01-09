//
//  WorkoutPlanOnboardingStepView.swift
//  Plates
//
//  Optional onboarding step for creating a workout plan
//

import SwiftUI

struct WorkoutPlanOnboardingStepView: View {
    @Binding var wantsWorkoutPlan: Bool?
    @Binding var workoutPlan: WorkoutPlan?
    @Binding var daysPerWeek: Int
    @Binding var experienceLevel: WorkoutPlanGenerationRequest.ExperienceLevel
    @Binding var equipmentAccess: WorkoutPlanGenerationRequest.EquipmentAccess
    @Binding var timePerSession: Int
    @Binding var workoutNotes: String

    let userProfile: PlanGenerationRequest?
    let isGenerating: Bool
    let onGenerate: () -> Void

    @State private var headerVisible = false
    @State private var contentVisible = false
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                    .padding(.top, 16)

                if wantsWorkoutPlan == nil {
                    decisionSection
                        .offset(y: contentVisible ? 0 : 30)
                        .opacity(contentVisible ? 1 : 0)
                } else if wantsWorkoutPlan == true {
                    if workoutPlan == nil && !isGenerating {
                        preferencesSection
                            .offset(y: contentVisible ? 0 : 30)
                            .opacity(contentVisible ? 1 : 0)
                    } else if isGenerating {
                        generatingSection
                    } else if let plan = workoutPlan {
                        reviewSection(plan)
                            .offset(y: contentVisible ? 0 : 30)
                            .opacity(contentVisible ? 1 : 0)
                    }
                }

                Color.clear.frame(height: 120)
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
            contentVisible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.15), lineWidth: 2)
                    .frame(width: 95, height: 95)
                    .scaleEffect(headerVisible ? 1 : 0.5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.15), Color.red.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(headerVisible ? 1 : 0.8)

            Text(headerTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    private var headerTitle: String {
        if wantsWorkoutPlan == nil {
            return "Workout Plan?"
        } else if workoutPlan == nil {
            return "Your Preferences"
        } else {
            return "Your Workout Plan"
        }
    }

    private var headerSubtitle: String {
        if wantsWorkoutPlan == nil {
            return "Would you like Trai to create a personalized workout plan?"
        } else if workoutPlan == nil {
            return "Tell us about your workout preferences"
        } else {
            return "Here's your personalized training program"
        }
    }

    // MARK: - Decision Section

    private var decisionSection: some View {
        VStack(spacing: 16) {
            DecisionCard(
                title: "Yes, create my plan",
                subtitle: "Get a personalized workout program based on your goals",
                icon: "sparkles",
                color: .orange
            ) {
                HapticManager.lightTap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    wantsWorkoutPlan = true
                }
            }

            DecisionCard(
                title: "Skip for now",
                subtitle: "You can always create a plan later in the Workouts tab",
                icon: "arrow.right.circle",
                color: .secondary
            ) {
                HapticManager.lightTap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    wantsWorkoutPlan = false
                }
            }
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(spacing: 20) {
            // Days per week
            PreferenceCard(title: "Days per Week", icon: "calendar") {
                Picker("Days per week", selection: $daysPerWeek) {
                    ForEach(2...6, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Experience level
            PreferenceCard(title: "Experience Level", icon: "figure.walk") {
                VStack(spacing: 8) {
                    ForEach(WorkoutPlanGenerationRequest.ExperienceLevel.allCases) { level in
                        ExperienceButton(
                            level: level,
                            isSelected: experienceLevel == level
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                experienceLevel = level
                            }
                        }
                    }
                }
            }

            // Equipment access
            PreferenceCard(title: "Equipment Access", icon: "dumbbell") {
                VStack(spacing: 8) {
                    ForEach(WorkoutPlanGenerationRequest.EquipmentAccess.allCases) { equipment in
                        EquipmentButton(
                            equipment: equipment,
                            isSelected: equipmentAccess == equipment
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                equipmentAccess = equipment
                            }
                        }
                    }
                }
            }

            // Time per session
            PreferenceCard(title: "Time per Session", icon: "clock") {
                Stepper("~\(timePerSession) minutes", value: $timePerSession, in: 20...90, step: 5)
            }

            // Additional notes (open-ended)
            PreferenceCard(title: "Anything Else?", icon: "text.bubble") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Focus areas, injuries, preferences...", text: $workoutNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .focused($isNotesFocused)

                    Text("E.g., \"Focus on chest and arms\", \"Bad lower back\", \"Prefer compound lifts\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Generate button
            Button {
                isNotesFocused = false
                onGenerate()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Generate My Plan")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.top, 8)
        }
    }

    // MARK: - Generating Section

    private var generatingSection: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Trai is creating your plan...")
                .font(.headline)

            Text("Designing a personalized workout program for you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(minHeight: 300)
    }

    // MARK: - Review Section

    private func reviewSection(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 20) {
            // Plan summary
            VStack(spacing: 16) {
                Image(systemName: plan.splitType.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text(plan.splitType.displayName)
                    .font(.title2)
                    .bold()

                HStack(spacing: 24) {
                    VStack {
                        Text("\(plan.daysPerWeek)")
                            .font(.title)
                            .bold()
                        Text("days/week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack {
                        Text("\(plan.templates.count)")
                            .font(.title)
                            .bold()
                        Text("workouts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))

            // Templates preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Workouts")
                    .font(.headline)

                ForEach(plan.templates.prefix(3)) { template in
                    HStack {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)

                        Text(template.name)
                            .font(.subheadline)

                        Spacer()

                        Text("\(template.exerciseCount) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(cornerRadius: 8))
                }
            }

            // Rationale
            VStack(alignment: .leading, spacing: 8) {
                Text("Why This Plan?")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(plan.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}

// MARK: - Decision Card

private struct DecisionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(isPressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
        }
    }
}

// MARK: - Preference Card

private struct PreferenceCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Experience Button

private struct ExperienceButton: View {
    let level: WorkoutPlanGenerationRequest.ExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Equipment Button

private struct EquipmentButton: View {
    let equipment: WorkoutPlanGenerationRequest.EquipmentAccess
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: equipment.iconName)
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(equipment.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(equipment.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WorkoutPlanOnboardingStepView(
        wantsWorkoutPlan: .constant(nil),
        workoutPlan: .constant(nil),
        daysPerWeek: .constant(3),
        experienceLevel: .constant(.beginner),
        equipmentAccess: .constant(.fullGym),
        timePerSession: .constant(45),
        workoutNotes: .constant(""),
        userProfile: nil,
        isGenerating: false,
        onGenerate: {}
    )
}
