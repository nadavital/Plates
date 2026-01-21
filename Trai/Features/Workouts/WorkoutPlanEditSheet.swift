//
//  WorkoutPlanEditSheet.swift
//  Trai
//
//  Quick edit sheet for existing workout plans (not full setup flow)
//

import SwiftUI
import SwiftData

struct WorkoutPlanEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    let currentPlan: WorkoutPlan

    @State private var showingChat = false
    @State private var showingFullSetup = false
    @State private var editedPlan: WorkoutPlan

    init(currentPlan: WorkoutPlan) {
        self.currentPlan = currentPlan
        self._editedPlan = State(initialValue: currentPlan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current plan summary
                    currentPlanCard

                    // Quick actions
                    quickActionsSection

                    // Templates overview
                    templatesSection

                    // Full redo option
                    startOverSection
                }
                .padding()
            }
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            WorkoutPlanChatFlow()
        }
        .fullScreenCover(isPresented: $showingFullSetup) {
            WorkoutPlanChatFlow()
        }
    }

    // MARK: - Current Plan Card

    private var currentPlanCard: some View {
        VStack(spacing: 16) {
            Image(systemName: currentPlan.splitType.iconName)
                .font(.largeTitle)
                .foregroundStyle(.accent)

            Text(currentPlan.splitType.displayName)
                .font(.title2)
                .bold()

            HStack(spacing: 24) {
                VStack {
                    Text("\(currentPlan.daysPerWeek)")
                        .font(.title)
                        .bold()
                    Text("days/week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("\(currentPlan.templates.count)")
                        .font(.title)
                        .bold()
                    Text("workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("~\(currentPlan.templates.first?.estimatedDurationMinutes ?? 45)")
                        .font(.title)
                        .bold()
                    Text("min each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            // Chat with Trai - main action
            Button {
                showingChat = true
            } label: {
                HStack(spacing: 12) {
                    TraiLensView(state: .idle, palette: .energy)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat with Trai")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Ask to swap exercises, adjust volume, change focus...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Quick suggestions
            VStack(spacing: 8) {
                QuickEditSuggestion(
                    text: "Change an exercise",
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    showingChat = true
                }

                QuickEditSuggestion(
                    text: "Adjust sets or reps",
                    icon: "slider.horizontal.3"
                ) {
                    showingChat = true
                }

                QuickEditSuggestion(
                    text: "Add/remove a workout day",
                    icon: "calendar.badge.plus"
                ) {
                    showingChat = true
                }
            }
        }
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Workouts")
                .font(.headline)

            ForEach(editedPlan.templates) { template in
                TemplateEditRow(template: template)
            }
        }
    }

    // MARK: - Start Over Section

    private var startOverSection: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 8)

            Button {
                showingFullSetup = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start Fresh")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Text("Create a completely new plan from scratch")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func buildRequest() -> WorkoutPlanGenerationRequest {
        let profile = userProfile
        return WorkoutPlanGenerationRequest(
            name: profile?.name ?? "User",
            age: profile?.age ?? 30,
            gender: profile?.genderValue ?? .notSpecified,
            goal: profile?.goal ?? .health,
            activityLevel: profile?.activityLevelValue ?? .moderate,
            workoutType: .strength,
            selectedWorkoutTypes: nil,
            experienceLevel: profile?.workoutExperience ?? .intermediate,
            equipmentAccess: profile?.workoutEquipment ?? .fullGym,
            availableDays: currentPlan.daysPerWeek,
            timePerWorkout: currentPlan.templates.first?.estimatedDurationMinutes ?? 45,
            preferredSplit: nil,
            cardioTypes: nil,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: nil,
            weakPoints: nil,
            injuries: nil,
            preferences: nil
        )
    }

    private func savePlan(_ plan: WorkoutPlan) {
        guard let profile = userProfile else { return }
        profile.workoutPlan = plan
        try? modelContext.save()
    }
}

// MARK: - Quick Edit Suggestion Button

private struct QuickEditSuggestion: View {
    let text: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.accent)
                    .frame(width: 24)

                Text(text)
                    .font(.subheadline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Edit Row

private struct TemplateEditRow: View {
    let template: WorkoutPlan.WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(template.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(template.muscleGroupsDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Exercise list preview
            HStack {
                ForEach(template.exercises.prefix(3)) { exercise in
                    Text(exercise.exerciseName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.capsule)
                }

                if template.exercises.count > 3 {
                    Text("+\(template.exercises.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    WorkoutPlanEditSheet(
        currentPlan: WorkoutPlan(
            splitType: .pushPullLegs,
            daysPerWeek: 3,
            templates: [
                WorkoutPlan.WorkoutTemplate(
                    name: "Push Day",
                    targetMuscleGroups: ["chest", "shoulders", "triceps"],
                    exercises: [
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Bench Press", muscleGroup: "chest", defaultSets: 4, defaultReps: 8, order: 0),
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Shoulder Press", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 10, order: 1),
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Tricep Pushdowns", muscleGroup: "triceps", defaultSets: 3, defaultReps: 12, order: 2),
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Lateral Raises", muscleGroup: "shoulders", defaultSets: 3, defaultReps: 15, order: 3)
                    ],
                    estimatedDurationMinutes: 45,
                    order: 0
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Pull Day",
                    targetMuscleGroups: ["back", "biceps"],
                    exercises: [
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Pull-ups", muscleGroup: "back", defaultSets: 4, defaultReps: 8, order: 0),
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Barbell Rows", muscleGroup: "back", defaultSets: 4, defaultReps: 8, order: 1),
                        WorkoutPlan.ExerciseTemplate(exerciseName: "Bicep Curls", muscleGroup: "biceps", defaultSets: 3, defaultReps: 12, order: 2)
                    ],
                    estimatedDurationMinutes: 45,
                    order: 1
                )
            ],
            rationale: "A classic PPL split",
            guidelines: [],
            progressionStrategy: .defaultStrategy,
            warnings: nil
        )
    )
    .modelContainer(for: [UserProfile.self], inMemory: true)
}
