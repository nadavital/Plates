//
//  WorkoutPlanSetupSheet.swift
//  Plates
//
//  Sheet for creating or editing a workout plan
//

import SwiftUI
import SwiftData

struct WorkoutPlanSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    @State private var geminiService = GeminiService()

    // Preferences
    @State private var daysPerWeek: Int = 3
    @State private var experienceLevel: WorkoutPlanGenerationRequest.ExperienceLevel = .beginner
    @State private var equipmentAccess: WorkoutPlanGenerationRequest.EquipmentAccess = .fullGym
    @State private var timePerSession: Int = 45
    @State private var workoutNotes: String = ""

    // Generation state
    @State private var isGenerating = false
    @State private var generatedPlan: WorkoutPlan?
    @State private var error: String?

    // Chat state
    @State private var showingChat = false

    // Phase
    @State private var currentPhase: SetupPhase = .preferences

    enum SetupPhase {
        case preferences
        case generating
        case review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentPhase {
                case .preferences:
                    preferencesView
                case .generating:
                    generatingView
                case .review:
                    if let plan = generatedPlan {
                        reviewView(plan)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if currentPhase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            savePlan()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(currentPhase == .generating)
        .sheet(isPresented: $showingChat) {
            if var plan = generatedPlan {
                WorkoutPlanChatView(
                    currentPlan: Binding(
                        get: { plan },
                        set: { plan = $0 }
                    ),
                    request: buildPlanRequest(),
                    onPlanUpdated: { updatedPlan in
                        generatedPlan = updatedPlan
                    }
                )
            }
        }
    }

    private var navigationTitle: String {
        switch currentPhase {
        case .preferences: "Create Workout Plan"
        case .generating: "Creating Plan"
        case .review: "Your Plan"
        }
    }

    // MARK: - Preferences View

    private var preferencesView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How many days per week can you work out?")
                        .font(.subheadline)

                    Picker("Days per week", selection: $daysPerWeek) {
                        ForEach(2...6, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Schedule", systemImage: "calendar")
            }

            Section {
                ForEach(WorkoutPlanGenerationRequest.ExperienceLevel.allCases) { level in
                    Button {
                        experienceLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.body)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if experienceLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Label("Experience Level", systemImage: "figure.walk")
            }

            Section {
                ForEach(WorkoutPlanGenerationRequest.EquipmentAccess.allCases) { equipment in
                    Button {
                        equipmentAccess = equipment
                    } label: {
                        HStack {
                            Image(systemName: equipment.iconName)
                                .frame(width: 24)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(equipment.displayName)
                                    .font(.body)
                                Text(equipment.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if equipmentAccess == equipment {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Label("Equipment Access", systemImage: "dumbbell")
            }

            Section {
                Stepper("~\(timePerSession) minutes", value: $timePerSession, in: 20...90, step: 5)
            } header: {
                Label("Time Per Session", systemImage: "clock")
            }

            Section {
                TextField("Focus areas, injuries, preferences...", text: $workoutNotes, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Label("Anything Else?", systemImage: "text.bubble")
            } footer: {
                Text("E.g., \"Focus on chest and arms\", \"Bad lower back\", \"Prefer compound lifts\"")
            }

            Section {
                Button {
                    generatePlan()
                } label: {
                    HStack {
                        Spacer()
                        Label("Create My Plan", systemImage: "sparkles")
                            .bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Trai is creating your plan...")
                .font(.headline)

            Text("Analyzing your goals and designing a personalized workout program")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Review View

    private func reviewView(_ plan: WorkoutPlan) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Plan summary card
                planSummaryCard(plan)

                // Templates
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Workouts")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(plan.templates) { template in
                        templatePreviewCard(template)
                    }
                }

                // Rationale
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why This Plan?")
                        .font(.headline)

                    Text(plan.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal)

                // Guidelines
                if !plan.guidelines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guidelines")
                            .font(.headline)

                        ForEach(plan.guidelines, id: \.self) { guideline in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(guideline)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Chat with Trai button
                    Button {
                        showingChat = true
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.fill")
                            Text("Customize with Trai")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)

                    // Regenerate button
                    Button {
                        currentPhase = .preferences
                    } label: {
                        Label("Adjust Preferences", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
            }
            .padding(.vertical)
        }
    }

    private func planSummaryCard(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 16) {
            Image(systemName: plan.splitType.iconName)
                .font(.largeTitle)
                .foregroundStyle(.accent)

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

                VStack {
                    Text("~\(plan.templates.first?.estimatedDurationMinutes ?? 45)")
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
        .padding(.horizontal)
    }

    private func templatePreviewCard(_ template: WorkoutPlan.WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name)
                    .font(.headline)
                Spacer()
                Text("\(template.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(template.muscleGroupsDisplay)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(template.exercises.prefix(4)) { exercise in
                HStack {
                    Text(exercise.exerciseName)
                        .font(.subheadline)
                    Spacer()
                    Text(exercise.setsRepsDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if template.exercises.count > 4 {
                Text("+\(template.exercises.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func buildPlanRequest() -> WorkoutPlanGenerationRequest {
        let profile = userProfile
        let trimmedNotes = workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusAreas = parseFocusAreas(from: trimmedNotes)
        let injuryNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        return WorkoutPlanGenerationRequest(
            name: profile?.name ?? "User",
            age: profile?.age ?? 30,
            gender: profile?.genderValue ?? .notSpecified,
            goal: profile?.goal ?? .health,
            activityLevel: profile?.activityLevelValue ?? .moderate,
            workoutType: .strength,
            selectedWorkoutTypes: nil,
            experienceLevel: experienceLevel,
            equipmentAccess: equipmentAccess,
            availableDays: daysPerWeek,
            timePerWorkout: timePerSession,
            preferredSplit: nil,
            cardioTypes: nil,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: focusAreas.isEmpty ? nil : focusAreas,
            weakPoints: nil,
            injuries: injuryNotes,
            preferences: nil
        )
    }

    private func parseFocusAreas(from notes: String) -> [String] {
        let lowercased = notes.lowercased()
        var areas: [String] = []

        let muscleKeywords: [(keyword: String, area: String)] = [
            ("chest", "chest"),
            ("back", "back"),
            ("shoulder", "shoulders"),
            ("arm", "arms"),
            ("bicep", "biceps"),
            ("tricep", "triceps"),
            ("leg", "legs"),
            ("quad", "quads"),
            ("hamstring", "hamstrings"),
            ("glute", "glutes"),
            ("core", "core"),
            ("abs", "abs"),
            ("upper body", "upper body"),
            ("lower body", "lower body")
        ]

        for (keyword, area) in muscleKeywords {
            if lowercased.contains(keyword) && !areas.contains(area) {
                areas.append(area)
            }
        }

        return areas
    }

    private func generatePlan() {
        guard userProfile != nil else { return }

        currentPhase = .generating

        Task {
            let request = buildPlanRequest()

            do {
                let plan = try await geminiService.generateWorkoutPlan(request: request)
                generatedPlan = plan
                currentPhase = .review
            } catch {
                // Use fallback plan
                generatedPlan = WorkoutPlan.createDefault(from: request)
                currentPhase = .review
            }
        }
    }

    private func savePlan() {
        guard let profile = userProfile, let plan = generatedPlan else { return }

        profile.workoutPlan = plan
        profile.preferredWorkoutDays = daysPerWeek
        profile.workoutExperience = experienceLevel
        profile.workoutEquipment = equipmentAccess
        profile.workoutTimePerSession = timePerSession

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    WorkoutPlanSetupSheet()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
