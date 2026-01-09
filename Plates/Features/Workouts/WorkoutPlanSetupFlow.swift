//
//  WorkoutPlanSetupFlow.swift
//  Plates
//
//  Step-by-step flow for creating a workout plan
//

import SwiftUI
import SwiftData

struct WorkoutPlanSetupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    // MARK: - Step State

    @State private var currentStep: SetupStep = .workoutType
    @State private var isAnimating = false
    @State private var isNavigatingForward = true

    // MARK: - User Selections

    @State private var workoutTypes: Set<WorkoutPlanGenerationRequest.WorkoutType> = []
    @State private var experienceLevel: WorkoutPlanGenerationRequest.ExperienceLevel?
    @State private var equipmentAccess: WorkoutPlanGenerationRequest.EquipmentAccess?
    @State private var daysPerWeek: Int? = nil  // nil = flexible
    @State private var timePerSession: Int = 45
    @State private var preferredSplit: WorkoutPlanGenerationRequest.PreferredSplit?
    @State private var cardioTypes: Set<WorkoutPlanGenerationRequest.CardioType> = []

    // MARK: - Custom/Other Text Inputs

    @State private var customWorkoutType: String = ""
    @State private var customExperience: String = ""
    @State private var customEquipment: String = ""
    @State private var customCardioType: String = ""

    // MARK: - Conversational Data (from Trai)

    @State private var specificGoals: [String] = []
    @State private var weakPoints: [String] = []
    @State private var injuries: String = ""
    @State private var preferences: String = ""

    // MARK: - Generation State

    @State private var isGenerating = false
    @State private var generatedPlan: WorkoutPlan?
    @State private var showingChat = false

    // MARK: - Steps

    enum SetupStep: Int, CaseIterable {
        case workoutType = 0
        case experience = 1
        case equipment = 2
        case schedule = 3
        case split = 4        // Conditional: only for strength/mixed
        case cardio = 5       // Conditional: only for cardio/mixed
        case conversation = 6 // Trai asks follow-up questions
        case generating = 7
        case review = 8

        var title: String {
            switch self {
            case .workoutType: "Workout Type"
            case .experience: "Experience"
            case .equipment: "Equipment"
            case .schedule: "Schedule"
            case .split: "Training Split"
            case .cardio: "Cardio Preference"
            case .conversation: "Almost There"
            case .generating: "Creating Plan"
            case .review: "Your Plan"
            }
        }
    }

    // MARK: - Computed Properties

    private var totalSteps: Int {
        var count = 4 // workoutType, experience, equipment, schedule
        if shouldShowSplitStep { count += 1 }
        if shouldShowCardioStep { count += 1 }
        count += 1 // conversation
        return count
    }

    private var currentStepIndex: Int {
        switch currentStep {
        case .workoutType: return 0
        case .experience: return 1
        case .equipment: return 2
        case .schedule: return 3
        case .split: return 4
        case .cardio: return shouldShowSplitStep ? 5 : 4
        case .conversation:
            var idx = 4
            if shouldShowSplitStep { idx += 1 }
            if shouldShowCardioStep { idx += 1 }
            return idx
        case .generating, .review: return totalSteps
        }
    }

    private var shouldShowSplitStep: Bool {
        workoutTypes.contains(.strength) || workoutTypes.contains(.mixed)
    }

    private var shouldShowCardioStep: Bool {
        workoutTypes.contains(.cardio) || workoutTypes.contains(.mixed) || workoutTypes.contains(.hiit)
    }

    private var canProceed: Bool {
        switch currentStep {
        case .workoutType: return !workoutTypes.isEmpty || !customWorkoutType.isEmpty
        case .experience: return experienceLevel != nil || !customExperience.isEmpty
        case .equipment: return equipmentAccess != nil || !customEquipment.isEmpty
        case .schedule: return true  // Always can proceed, flexible is valid
        case .split: return preferredSplit != nil
        case .cardio: return !cardioTypes.isEmpty || !customCardioType.isEmpty
        case .conversation: return true
        default: return false
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar (hidden during generation/review)
                    if currentStep != .generating && currentStep != .review {
                        progressBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Step content
                    stepContent
                        .frame(maxHeight: .infinity)

                    // Navigation buttons (hidden during generation/review)
                    if currentStep != .generating && currentStep != .review {
                        navigationButtons
                            .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep != .generating {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == .review {
                        Button("Save") {
                            savePlan()
                        }
                        .bold()
                    }
                }
            }
            .interactiveDismissDisabled(currentStep == .generating)
            .sheet(isPresented: $showingChat) {
                if let plan = generatedPlan {
                    WorkoutPlanChatView(
                        currentPlan: Binding(
                            get: { plan },
                            set: { generatedPlan = $0 }
                        ),
                        request: buildRequest(),
                        onPlanUpdated: { generatedPlan = $0 }
                    )
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(currentStepIndex + 1) / CGFloat(totalSteps), height: 4)
                    .animation(.spring(response: 0.4), value: currentStepIndex)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step Content

    /// Transition based on navigation direction
    private var stepTransition: AnyTransition {
        if isNavigatingForward {
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        } else {
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .workoutType:
            WorkoutTypeStepView(selection: $workoutTypes, customText: $customWorkoutType)
                .transition(stepTransition)

        case .experience:
            ExperienceStepView(selection: $experienceLevel, customText: $customExperience)
                .transition(stepTransition)

        case .equipment:
            EquipmentStepView(selection: $equipmentAccess, customText: $customEquipment)
                .transition(stepTransition)

        case .schedule:
            ScheduleStepView(daysPerWeek: $daysPerWeek, timePerSession: $timePerSession)
                .transition(stepTransition)

        case .split:
            SplitStepView(selection: $preferredSplit)
                .transition(stepTransition)

        case .cardio:
            CardioStepView(selection: $cardioTypes, customText: $customCardioType)
                .transition(stepTransition)

        case .conversation:
            ConversationStepView(
                specificGoals: $specificGoals,
                weakPoints: $weakPoints,
                injuries: $injuries,
                preferences: $preferences,
                workoutTypes: workoutTypes,
                onComplete: { generatePlan() }
            )
            .transition(stepTransition)

        case .generating:
            GeneratingStepView()
                .transition(.opacity)

        case .review:
            if let plan = generatedPlan {
                ReviewStepView(
                    plan: plan,
                    onCustomize: { showingChat = true },
                    onRestart: { restartFlow() }
                )
                .transition(stepTransition)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Back button
            if currentStep != .workoutType {
                Button {
                    goBack()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }

            // Continue button
            if currentStep != .conversation {
                Button {
                    goNext()
                } label: {
                    Text(currentStep == .schedule ? "Continue" : "Next")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accent)
                .disabled(!canProceed)
            }
        }
    }

    // MARK: - Navigation

    private func goNext() {
        guard canProceed else { return }
        HapticManager.lightTap()

        isNavigatingForward = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch currentStep {
            case .workoutType:
                currentStep = .experience
            case .experience:
                currentStep = .equipment
            case .equipment:
                currentStep = .schedule
            case .schedule:
                if shouldShowSplitStep {
                    currentStep = .split
                } else if shouldShowCardioStep {
                    currentStep = .cardio
                } else {
                    currentStep = .conversation
                }
            case .split:
                if shouldShowCardioStep {
                    currentStep = .cardio
                } else {
                    currentStep = .conversation
                }
            case .cardio:
                currentStep = .conversation
            default:
                break
            }
        }
    }

    private func goBack() {
        HapticManager.lightTap()

        isNavigatingForward = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch currentStep {
            case .experience:
                currentStep = .workoutType
            case .equipment:
                currentStep = .experience
            case .schedule:
                currentStep = .equipment
            case .split:
                currentStep = .schedule
            case .cardio:
                if shouldShowSplitStep {
                    currentStep = .split
                } else {
                    currentStep = .schedule
                }
            case .conversation:
                if shouldShowCardioStep {
                    currentStep = .cardio
                } else if shouldShowSplitStep {
                    currentStep = .split
                } else {
                    currentStep = .schedule
                }
            default:
                break
            }
        }
    }

    private func restartFlow() {
        isNavigatingForward = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = .workoutType
            generatedPlan = nil
        }
    }

    // MARK: - Plan Generation

    private func buildRequest() -> WorkoutPlanGenerationRequest {
        let profile = userProfile

        // Determine primary workout type - use .mixed if multiple selected or custom
        let primaryWorkoutType: WorkoutPlanGenerationRequest.WorkoutType
        if !customWorkoutType.isEmpty {
            primaryWorkoutType = .mixed  // Treat custom as mixed
        } else if workoutTypes.count == 1, let single = workoutTypes.first {
            primaryWorkoutType = single
        } else {
            primaryWorkoutType = .mixed
        }

        return WorkoutPlanGenerationRequest(
            name: profile?.name ?? "User",
            age: profile?.age ?? 30,
            gender: profile?.genderValue ?? .notSpecified,
            goal: profile?.goal ?? .health,
            activityLevel: profile?.activityLevelValue ?? .moderate,
            workoutType: primaryWorkoutType,
            selectedWorkoutTypes: workoutTypes.isEmpty ? nil : Array(workoutTypes),
            experienceLevel: experienceLevel,
            equipmentAccess: equipmentAccess,
            availableDays: daysPerWeek,
            timePerWorkout: timePerSession,
            preferredSplit: preferredSplit,
            cardioTypes: cardioTypes.isEmpty ? nil : Array(cardioTypes),
            customWorkoutType: customWorkoutType.isEmpty ? nil : customWorkoutType,
            customExperience: customExperience.isEmpty ? nil : customExperience,
            customEquipment: customEquipment.isEmpty ? nil : customEquipment,
            customCardioType: customCardioType.isEmpty ? nil : customCardioType,
            specificGoals: specificGoals.isEmpty ? nil : specificGoals,
            weakPoints: weakPoints.isEmpty ? nil : weakPoints,
            injuries: injuries.isEmpty ? nil : injuries,
            preferences: preferences.isEmpty ? nil : preferences
        )
    }

    private func generatePlan() {
        currentStep = .generating

        Task {
            let request = buildRequest()
            let service = GeminiService()

            do {
                let plan = try await service.generateWorkoutPlan(request: request)
                generatedPlan = plan
                withAnimation {
                    currentStep = .review
                }
                HapticManager.success()
            } catch {
                // Use fallback plan
                generatedPlan = WorkoutPlan.createDefault(from: request)
                withAnimation {
                    currentStep = .review
                }
            }
        }
    }

    private func savePlan() {
        guard let profile = userProfile, let plan = generatedPlan else { return }

        profile.workoutPlan = plan
        profile.preferredWorkoutDays = daysPerWeek ?? 3
        profile.workoutExperience = experienceLevel ?? .beginner
        profile.workoutEquipment = equipmentAccess ?? .fullGym
        profile.workoutTimePerSession = timePerSession

        try? modelContext.save()
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    WorkoutPlanSetupFlow()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
