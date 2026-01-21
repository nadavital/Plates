//
//  WorkoutPlanChatFlow.swift
//  Trai
//
//  Unified conversational flow for creating a workout plan
//

import SwiftUI
import SwiftData

struct WorkoutPlanChatFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    // MARK: - Mode Configuration

    /// When true, shows skip option and uses callbacks instead of direct save
    var isOnboarding: Bool = false

    /// When true, removes NavigationStack wrapper (for embedding)
    var embedded: Bool = false

    /// Called when plan is complete (onboarding mode only)
    var onComplete: ((WorkoutPlan) -> Void)?

    /// Called when user skips (onboarding mode only)
    var onSkip: (() -> Void)?

    // MARK: - State

    @State private var messages: [WorkoutPlanFlowMessage] = []
    @State private var collectedAnswers = TraiCollectedAnswers()
    @State private var currentAnswers: [String] = []
    @State private var inputText = ""
    @State private var currentQuestionIndex = 0
    @State private var isGenerating = false
    @State private var generatedPlan: WorkoutPlan?
    @State private var planAccepted = false
    @State private var showRefineMode = false
    @State private var isTransitioning = false  // For question transition animation

    @FocusState private var isInputFocused: Bool

    // MARK: - Question Flow

    private var allQuestions: [WorkoutPlanQuestion] {
        [.workoutType, .experience, .equipment, .schedule, .split, .cardio, .goals, .weakPoints, .injuries, .preferences]
    }

    private var visibleQuestions: [WorkoutPlanQuestion] {
        allQuestions.filter { $0.shouldShow(given: collectedAnswers) }
    }

    private var currentQuestion: WorkoutPlanQuestion? {
        guard currentQuestionIndex < visibleQuestions.count else { return nil }
        return visibleQuestions[currentQuestionIndex]
    }

    private var isLastQuestion: Bool {
        currentQuestionIndex >= visibleQuestions.count - 1
    }

    // MARK: - Body

    var body: some View {
        if embedded {
            mainContent
        } else {
            NavigationStack {
                mainContent
                    .navigationTitle("Create Your Plan")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            if !isOnboarding && !isGenerating {
                                Button("Cancel", systemImage: "xmark") {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .interactiveDismissDisabled(isGenerating)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Welcome message
                        welcomeMessage

                        // All messages
                        ForEach(messages) { message in
                            messageView(for: message)
                                .id(message.id)
                        }

                        // Current question options only (question text is added to messages)
                        // Hide after plan is generated (generatedPlan != nil means we're done with questions)
                        if let question = currentQuestion, !isGenerating && !planAccepted && !isTransitioning && generatedPlan == nil {
                            currentOptionsView(question: question)
                                .id("currentOptions")
                                .transition(.opacity)
                        }

                        // Thinking indicator
                        if isGenerating {
                            ThinkingIndicator(activity: "Creating your personalized plan...")
                                .id("thinking")
                        }

                        // Bottom anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor")
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isGenerating) { _, generating in
                    if generating {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: isTransitioning) { _, transitioning in
                    // Scroll when new question appears
                    if !transitioning {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(proxy)
                        }
                    }
                }
                .onChange(of: currentQuestionIndex) { _, _ in
                    // Scroll when question changes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollToBottom(proxy)
                    }
                }
            }

            // Input bar
            if !isGenerating {
                inputBar
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            isInputFocused = false
        }
        .onAppear {
            // Start with first question
            if messages.isEmpty {
                addQuestionMessage()
            }
        }
    }

    // MARK: - Welcome Message

    private var welcomeMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            TraiLensView(size: 36, state: .idle, palette: .energy)

            Text("Let's build your perfect workout plan! I'll ask you a few questions to personalize everything.")
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Message Views

    @ViewBuilder
    private func messageView(for message: WorkoutPlanFlowMessage) -> some View {
        switch message.type {
        case .question(let config):
            // Past questions (already answered)
            Text(config.question)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .userAnswer(let answers):
            userAnswerBubble(answers: answers)

        case .thinking(let activity):
            ThinkingIndicator(activity: activity)

        case .planProposal(let plan, let message):
            WorkoutPlanProposalCard(
                plan: plan,
                message: message,
                onAccept: { acceptPlan() },
                onCustomize: showRefineMode ? nil : { enterRefineMode() }
            )

        case .planAccepted:
            WorkoutPlanAcceptedBadge()

        case .traiMessage(let text):
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .planUpdated:
            WorkoutPlanUpdatedBadge()

        case .error(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func userAnswerBubble(answers: [String]) -> some View {
        HStack {
            Spacer()

            Text(answers.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(.rect(cornerRadius: 18))
        }
    }

    // MARK: - Current Options View

    /// Only shows the selectable options (question text is shown separately above)
    private func currentOptionsView(question: WorkoutPlanQuestion) -> some View {
        VStack(spacing: 16) {
            TraiSuggestionChips(
                suggestions: question.config.suggestions,
                selectionMode: question.config.selectionMode,
                selectedAnswers: currentAnswers,
                onTap: { suggestion in
                    handleSuggestionTap(suggestion)
                }
            )

            // Selected answers as removable tags (for multi-select with custom answers)
            if question.config.selectionMode == .multiple && !currentAnswers.isEmpty {
                TraiSelectedAnswerTags(
                    answers: currentAnswers,
                    suggestions: question.config.suggestions.map(\.text),
                    onRemove: { answer in
                        currentAnswers.removeAll { $0 == answer }
                    }
                )
            }
        }
    }

    private func handleSuggestionTap(_ suggestion: TraiSuggestion) {
        HapticManager.lightTap()

        if let question = currentQuestion {
            switch question.config.selectionMode {
            case .single:
                currentAnswers = [suggestion.text]
            case .multiple:
                if currentAnswers.contains(suggestion.text) {
                    currentAnswers.removeAll { $0 == suggestion.text }
                } else {
                    currentAnswers.append(suggestion.text)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        Group {
            if planAccepted && showRefineMode {
                // Freeform chat mode after plan accepted
                SimpleChatInputBar(
                    text: $inputText,
                    placeholder: "Ask me to adjust anything...",
                    isLoading: isGenerating,
                    onSend: { handleRefineMessage() },
                    isFocused: $isInputFocused
                )
            } else if !planAccepted {
                // Question mode
                TraiQuestionInputBar(
                    text: $inputText,
                    placeholder: currentQuestion?.config.placeholder ?? "Type your answer...",
                    hasAnswers: !currentAnswers.isEmpty,
                    isLastQuestion: isLastQuestion,
                    isLoading: isGenerating,
                    onSend: { handleCustomInput() },
                    onContinue: { handleContinue() },
                    onSkip: { handleSkip() },
                    isFocused: $isInputFocused
                )
            } else {
                // Plan accepted, show done options
                planAcceptedBar
            }
        }
    }

    private var planAcceptedBar: some View {
        VStack(spacing: 12) {
            // Customize button
            Button {
                enterRefineMode()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Customize Plan")
                }
                .font(.subheadline)
                .fontWeight(.medium)
            }
            .buttonStyle(.bordered)

            // Done button
            Button {
                savePlan()
            } label: {
                HStack(spacing: 8) {
                    Text(isOnboarding ? "Continue" : "Done")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)

            // Skip button (onboarding only)
            if isOnboarding {
                Button {
                    onSkip?()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func addQuestionMessage() {
        guard let question = currentQuestion else { return }
        // Don't add duplicate question messages
        let alreadyAdded = messages.contains { msg in
            if case .question(let config) = msg.type {
                return config.id == question.config.id
            }
            return false
        }
        if !alreadyAdded {
            messages.append(WorkoutPlanFlowMessage(type: .question(question.config)))
        }
    }

    private func handleContinue() {
        guard !currentAnswers.isEmpty || isLastQuestion else {
            handleSkip()
            return
        }

        HapticManager.lightTap()

        // Save current answers
        guard let question = currentQuestion else { return }
        for answer in currentAnswers {
            collectedAnswers.add(answer, for: question.rawValue)
        }

        // Store values before clearing
        let answersToShow = currentAnswers
        let wasLastQuestion = isLastQuestion

        // Step 1: Fade out options
        withAnimation(.easeOut(duration: 0.2)) {
            isTransitioning = true
        }

        // Step 2: After fade, add the answer (question is already in messages)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !answersToShow.isEmpty {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    messages.append(WorkoutPlanFlowMessage(type: .userAnswer(answersToShow)))
                }
            }

            currentAnswers = []

            // Step 3: Move to next question (which adds its text to messages)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if wasLastQuestion {
                    isTransitioning = false
                    generatePlan()
                } else {
                    currentQuestionIndex += 1
                    addQuestionMessage()  // Add next question text
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isTransitioning = false
                    }
                }
            }
        }
    }

    private func handleSkip() {
        HapticManager.lightTap()

        // Store before clearing
        let wasLastQuestion = isLastQuestion

        // Clear any partial selections
        currentAnswers = []

        // Step 1: Fade out options
        withAnimation(.easeOut(duration: 0.2)) {
            isTransitioning = true
        }

        // Step 2: Move to next question (question text already in messages, no answer for skip)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if wasLastQuestion {
                isTransitioning = false
                generatePlan()
            } else {
                currentQuestionIndex += 1
                addQuestionMessage()  // Add next question text
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isTransitioning = false
                }
            }
        }
    }

    private func handleCustomInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        HapticManager.lightTap()

        // Add custom answer
        currentAnswers.append(text)
        inputText = ""
        isInputFocused = false

        // Auto-continue after custom input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            handleContinue()
        }
    }

    private func generatePlan() {
        isGenerating = true

        Task {
            let request = buildRequest()
            let service = GeminiService()

            do {
                let plan = try await service.generateWorkoutPlan(request: request)
                generatedPlan = plan

                withAnimation(.spring(response: 0.3)) {
                    // Show Trai's intro message separately
                    messages.append(WorkoutPlanFlowMessage(
                        type: .traiMessage(generatePlanIntroMessage(for: plan))
                    ))
                    // Then show the plan card
                    messages.append(WorkoutPlanFlowMessage(
                        type: .planProposal(plan, "")
                    ))
                    isGenerating = false
                }
                HapticManager.success()
            } catch {
                // Use fallback plan
                let fallbackPlan = WorkoutPlan.createDefault(from: request)
                generatedPlan = fallbackPlan

                withAnimation(.spring(response: 0.3)) {
                    messages.append(WorkoutPlanFlowMessage(
                        type: .traiMessage("Here's a solid plan based on what you told me!")
                    ))
                    messages.append(WorkoutPlanFlowMessage(
                        type: .planProposal(fallbackPlan, "")
                    ))
                    isGenerating = false
                }
            }
        }
    }

    /// Generate a personalized intro message for the plan
    private func generatePlanIntroMessage(for plan: WorkoutPlan) -> String {
        let splitName = plan.splitType.displayName
        let days = plan.daysPerWeek

        // Use rationale if available, otherwise generate based on plan
        if !plan.rationale.isEmpty {
            return plan.rationale
        }

        // Generate a contextual message
        let workoutTypes = collectedAnswers.answers(for: "workoutType")
        if workoutTypes.contains("Mixed") || workoutTypes.count > 1 {
            return "I've put together a \(splitName) split that balances everything you want - \(days) days per week with a good mix of training styles."
        } else if workoutTypes.contains("Strength") {
            return "Based on your goals, I've designed a \(splitName) split - \(days) days per week focused on building strength and muscle."
        } else if workoutTypes.contains("Cardio") {
            return "Here's a \(days)-day plan that'll keep your cardio on track while building overall fitness."
        } else {
            return "I've created a \(splitName) program for you - \(days) days per week tailored to your goals and schedule."
        }
    }

    private func acceptPlan() {
        HapticManager.success()

        withAnimation(.spring(response: 0.3)) {
            messages.append(WorkoutPlanFlowMessage(type: .planAccepted))
            planAccepted = true
        }
    }

    private func enterRefineMode() {
        showRefineMode = true

        withAnimation(.spring(response: 0.3)) {
            messages.append(WorkoutPlanFlowMessage(
                type: .traiMessage("Sure! Tell me what you'd like to change.")
            ))
        }
    }

    private func handleRefineMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let currentPlan = generatedPlan else { return }

        // Clear text immediately before anything else
        let messageText = text
        inputText = ""
        isInputFocused = false

        // Add user message
        withAnimation(.spring(response: 0.3)) {
            messages.append(WorkoutPlanFlowMessage(type: .userAnswer([messageText])))
        }
        isGenerating = true

        Task {
            let request = buildRequest()
            let service = GeminiService()

            do {
                let response = try await service.refineWorkoutPlan(
                    currentPlan: currentPlan,
                    request: request,
                    userMessage: text,
                    conversationHistory: []
                )

                withAnimation(.spring(response: 0.3)) {
                    if let newPlan = response.proposedPlan ?? response.updatedPlan {
                        generatedPlan = newPlan
                        messages.append(WorkoutPlanFlowMessage(
                            type: .planProposal(newPlan, response.message)
                        ))
                    } else {
                        messages.append(WorkoutPlanFlowMessage(
                            type: .traiMessage(response.message)
                        ))
                    }
                    isGenerating = false
                }
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    messages.append(WorkoutPlanFlowMessage(
                        type: .error("Sorry, I couldn't process that. Try again?")
                    ))
                    isGenerating = false
                }
            }
        }
    }

    private func savePlan() {
        guard let plan = generatedPlan else { return }

        if isOnboarding {
            HapticManager.success()
            onComplete?(plan)
        } else {
            guard let profile = userProfile else { return }

            profile.workoutPlan = plan

            // Save schedule preferences
            if let days = parseDays(from: collectedAnswers.answers(for: "schedule")) {
                profile.preferredWorkoutDays = days
            }
            if let experience = parseExperience(from: collectedAnswers.answers(for: "experience")) {
                profile.workoutExperience = experience
            }
            if let equipment = parseEquipment(from: collectedAnswers.answers(for: "equipment")) {
                profile.workoutEquipment = equipment
            }

            try? modelContext.save()
            HapticManager.success()
            dismiss()
        }
    }

    // MARK: - Build Request

    private func buildRequest() -> WorkoutPlanGenerationRequest {
        let profile = userProfile

        // Parse workout types
        let workoutTypeAnswers = collectedAnswers.answers(for: "workoutType")
        let workoutTypes = parseWorkoutTypes(from: workoutTypeAnswers)
        let primaryType: WorkoutPlanGenerationRequest.WorkoutType = workoutTypes.count == 1 ? workoutTypes.first ?? .mixed : .mixed

        // Parse other fields
        let experience = parseExperience(from: collectedAnswers.answers(for: "experience"))
        let equipment = parseEquipment(from: collectedAnswers.answers(for: "equipment"))
        let days = parseDays(from: collectedAnswers.answers(for: "schedule"))
        let split = parseSplit(from: collectedAnswers.answers(for: "split"))
        let cardioTypes = parseCardioTypes(from: collectedAnswers.answers(for: "cardio"))

        // Custom text from non-standard answers
        let customWorkoutType = workoutTypeAnswers.first { !["Strength", "Cardio", "HIIT", "Flexibility", "Mixed"].contains($0) }
        let customExperience = collectedAnswers.answers(for: "experience").first { !["Beginner", "Intermediate", "Advanced"].contains($0) }
        let customEquipment = collectedAnswers.answers(for: "equipment").first { !["Full Gym", "Home - Dumbbells", "Home - Full Setup", "Bodyweight Only"].contains($0) }

        return WorkoutPlanGenerationRequest(
            name: profile?.name ?? "User",
            age: profile?.age ?? 30,
            gender: profile?.genderValue ?? .notSpecified,
            goal: profile?.goal ?? .health,
            activityLevel: profile?.activityLevelValue ?? .moderate,
            workoutType: primaryType,
            selectedWorkoutTypes: workoutTypes.isEmpty ? nil : workoutTypes,
            experienceLevel: experience,
            equipmentAccess: equipment,
            availableDays: days,
            timePerWorkout: 45,
            preferredSplit: split,
            cardioTypes: cardioTypes.isEmpty ? nil : cardioTypes,
            customWorkoutType: customWorkoutType,
            customExperience: customExperience,
            customEquipment: customEquipment,
            customCardioType: nil,
            specificGoals: collectedAnswers.answers(for: "goals").isEmpty ? nil : collectedAnswers.answers(for: "goals"),
            weakPoints: collectedAnswers.answers(for: "weakPoints").isEmpty ? nil : collectedAnswers.answers(for: "weakPoints"),
            injuries: collectedAnswers.answers(for: "injuries").first,
            preferences: collectedAnswers.answers(for: "preferences").first
        )
    }

    // MARK: - Parsing Helpers

    private func parseWorkoutTypes(from answers: [String]) -> [WorkoutPlanGenerationRequest.WorkoutType] {
        answers.compactMap { answer in
            switch answer {
            case "Strength": return .strength
            case "Cardio": return .cardio
            case "HIIT": return .hiit
            case "Flexibility": return .flexibility
            case "Mixed": return .mixed
            default: return nil
            }
        }
    }

    private func parseExperience(from answers: [String]) -> WorkoutPlanGenerationRequest.ExperienceLevel? {
        guard let answer = answers.first else { return nil }
        switch answer {
        case "Beginner": return .beginner
        case "Intermediate": return .intermediate
        case "Advanced": return .advanced
        default: return nil
        }
    }

    private func parseEquipment(from answers: [String]) -> WorkoutPlanGenerationRequest.EquipmentAccess? {
        guard let answer = answers.first else { return nil }
        switch answer {
        case "Full Gym": return .fullGym
        case "Home - Dumbbells": return .homeBasic
        case "Home - Full Setup": return .homeAdvanced
        case "Bodyweight Only": return .bodyweightOnly
        default: return nil
        }
    }

    private func parseDays(from answers: [String]) -> Int? {
        guard let answer = answers.first else { return nil }
        if answer == "Flexible" { return nil }
        // Extract number from "2 days", "3 days", etc.
        let digits = answer.filter { $0.isNumber }
        return Int(digits)
    }

    private func parseSplit(from answers: [String]) -> WorkoutPlanGenerationRequest.PreferredSplit? {
        guard let answer = answers.first else { return nil }
        switch answer {
        case "Push/Pull/Legs": return .pushPullLegs
        case "Upper/Lower": return .upperLower
        case "Full Body": return .fullBody
        case "Bro Split": return .broSplit
        case "Let Trai decide": return .letTraiDecide
        default: return nil
        }
    }

    private func parseCardioTypes(from answers: [String]) -> [WorkoutPlanGenerationRequest.CardioType] {
        answers.compactMap { answer in
            switch answer {
            case "Running": return .running
            case "Cycling": return .cycling
            case "Swimming": return .swimming
            case "Rowing": return .rowing
            case "Jump Rope": return .jumpRope
            case "Anything works": return .anyCardio
            default: return nil
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutPlanChatFlow()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
