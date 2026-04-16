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
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    // MARK: - Mode Configuration

    /// When true, shows skip option and uses callbacks instead of direct save
    var isOnboarding: Bool = false

    /// When true, removes NavigationStack wrapper (for embedding)
    var embedded: Bool = false

    /// Existing saved plan to revise instead of starting from a blank questionnaire
    var currentPlanToEdit: WorkoutPlan? = nil

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
        [.workoutType, .schedule, .equipment, .background, .constraints]
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

    private var canAccessWorkoutAI: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private var isEditingExistingPlan: Bool {
        currentPlanToEdit != nil
    }

    private var navigationTitle: String {
        isEditingExistingPlan ? "Edit Your Plan" : "Create Your Plan"
    }

    private var requiresAuthenticatedAccountForWorkoutAI: Bool {
        accountSessionService?.isAuthenticated != true
    }

    private var shouldShowRefinementSuggestions: Bool {
        isEditingExistingPlan && showRefineMode && generatedPlan != nil && !isGenerating
    }

    private var refinementSuggestions: [TraiSuggestion] {
        [
            TraiSuggestion("Change the split", subtitle: "Try something like upper/lower or full body"),
            TraiSuggestion("Add a workout day", subtitle: "Increase frequency without starting over"),
            TraiSuggestion("Remove a day", subtitle: "Condense the plan into fewer sessions"),
            TraiSuggestion("Make workouts shorter", subtitle: "Trim the session length"),
            TraiSuggestion("Add more cardio", subtitle: "Layer conditioning into the week"),
            TraiSuggestion("Add more recovery", subtitle: "Make the week easier to sustain"),
            TraiSuggestion("Adapt this for home equipment", subtitle: "Swap gym work for what I have"),
            TraiSuggestion("Swap some exercises", subtitle: "Keep the structure but change the lifts")
        ]
    }

    private var thinkingActivityText: String {
        isEditingExistingPlan && showRefineMode
            ? "Updating your workout plan..."
            : "Creating your personalized plan..."
    }

    // MARK: - Body

    var body: some View {
        Group {
            if requiresAuthenticatedAccountForWorkoutAI {
                AccountSetupView(context: .aiFeatures, showsDismissButton: !embedded)
            } else if !canAccessWorkoutAI {
                ProUpsellView(source: .workoutPlan, showsDismissButton: !embedded)
            } else if embedded {
                mainContent
            } else {
                NavigationStack {
                    mainContent
                        .navigationTitle(navigationTitle)
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
        .traiSheetBranding()
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
                            ThinkingIndicator(activity: thinkingActivityText)
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
            if messages.isEmpty {
                if isEditingExistingPlan {
                    seedExistingPlanConversation()
                } else {
                    // Start with first question
                    addQuestionMessage()
                }
            }
        }
    }

    // MARK: - Welcome Message

    @ViewBuilder
    private var welcomeMessage: some View {
        if !isEditingExistingPlan {
            HStack(alignment: .top, spacing: 12) {
                TraiLensView(size: 36, state: .idle, palette: .energy)

                Text("Let's build a plan around the kinds of sessions you actually want to do. I'll ask only the essentials, then put together a first version you can tweak.")
                    .font(.subheadline)

                Spacer()
            }
        }
    }

    // MARK: - Message Views

    @ViewBuilder
    private func messageView(for message: WorkoutPlanFlowMessage) -> some View {
        switch message.type {
        case .question(let config):
            // Past questions (already answered)
            TraiAssistantTextMessage(text: config.question)

        case .userAnswer(let answers):
            userAnswerBubble(answers: answers)

        case .thinking(let activity):
            ThinkingIndicator(activity: activity)

        case .planProposal(let plan, let message):
            WorkoutPlanProposalCard(
                plan: plan,
                message: message,
                onAccept: { acceptPlan() },
                acceptTitle: isEditingExistingPlan ? "Save Changes" : "Use This Plan",
                onCustomize: isEditingExistingPlan || showRefineMode ? nil : { enterRefineMode() }
            )

        case .currentPlan(let plan, let message):
            WorkoutPlanProposalCard(
                plan: plan,
                message: message,
                onAccept: nil,
                onCustomize: nil
            )

        case .planAccepted:
            WorkoutPlanAcceptedBadge()

        case .traiMessage(let text):
            TraiAssistantTextMessage(text: text)

        case .planUpdated(_):
            WorkoutPlanUpdatedBadge()

        case .error(let text):
            TraiAssistantTextMessage(text: text, foregroundStyle: .red)
        }
    }

    private func userAnswerBubble(answers: [String]) -> some View {
        HStack {
            Spacer()

            TraiUserTextBubble(text: answers.joined(separator: ", "))
        }
    }

    private var refinementSuggestionView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(refinementSuggestions) { suggestion in
                    TraiSelectableChip(
                        text: suggestion.text,
                        isSelected: false,
                        action: {
                            HapticManager.lightTap()
                            submitRefineSuggestion(suggestion)
                        }
                    )
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color(.systemBackground))
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
                VStack(spacing: 6) {
                    if shouldShowRefinementSuggestions {
                        refinementSuggestionView
                    }

                    SimpleChatInputBar(
                        text: $inputText,
                        placeholder: isEditingExistingPlan ? "Tell me what you'd like to change..." : "Ask me to adjust anything...",
                        isLoading: isGenerating,
                        onSend: { handleRefineMessage() },
                        isFocused: $isInputFocused
                    )
                }
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
            .buttonStyle(.traiTertiary())

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
            .buttonStyle(.traiPrimary(fullWidth: true))

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

    private func seedExistingPlanConversation() {
        guard let plan = currentPlanToEdit else { return }

        generatedPlan = plan
        planAccepted = true
        showRefineMode = true

        messages.append(
            WorkoutPlanFlowMessage(
                type: .currentPlan(
                    plan,
                    "Here's your current plan. Tell me what you'd like to change and I'll revise it without making you start over."
                )
            )
        )
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
            let service = AIService()

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
            return "Here's a \(days)-day plan built around the conditioning work you want while keeping the week balanced."
        } else if workoutTypes.contains("Climbing") || workoutTypes.contains("Yoga") || workoutTypes.contains("Pilates") || workoutTypes.contains("Mobility") {
            let customFocus = workoutTypes.joined(separator: ", ")
            return "I've mapped out a \(days)-day plan centered on \(customFocus.lowercased()) with enough structure to keep it sustainable week to week."
        } else {
            return "I've created a \(splitName) program for you - \(days) days per week tailored to your goals and schedule."
        }
    }

    private func acceptPlan() {
        if isOnboarding || isEditingExistingPlan {
            savePlan()
            return
        }

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
        guard !text.isEmpty else { return }

        // Clear text immediately before anything else
        let messageText = text
        inputText = ""
        isInputFocused = false

        submitRefineRequest(messageText)
    }

    private func submitRefineSuggestion(_ suggestion: TraiSuggestion) {
        submitRefineRequest(suggestion.text)
    }

    private func submitRefineRequest(_ text: String) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, let currentPlan = generatedPlan else { return }

        // Add user message
        withAnimation(.spring(response: 0.3)) {
            messages.append(WorkoutPlanFlowMessage(type: .userAnswer([messageText])))
        }
        isGenerating = true

        Task {
            let request = buildRequest()
            let service = AIService()

            do {
                let response = try await service.refineWorkoutPlan(
                    currentPlan: currentPlan,
                    request: request,
                    userMessage: messageText,
                    conversationHistory: refinementConversationHistory
                )

                withAnimation(.spring(response: 0.3)) {
                    if let newPlan = response.proposedPlan ?? response.updatedPlan {
                        if newPlan != currentPlan {
                            messages.append(WorkoutPlanFlowMessage(
                                type: .planUpdated(newPlan)
                            ))
                        }
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

            if currentPlanToEdit == plan {
                HapticManager.success()
                dismiss()
                return
            }

            let hadExistingPlan = profile.workoutPlan != nil

            WorkoutPlanHistoryService.archiveCurrentPlanIfExists(
                profile: profile,
                reason: .chatAdjustment,
                modelContext: modelContext,
                replacingWith: plan
            )

            profile.workoutPlan = plan

            if !hadExistingPlan {
                WorkoutPlanHistoryService.archivePlan(
                    plan,
                    profile: profile,
                    reason: .chatCreate,
                    modelContext: modelContext
                )
            }

            // Save schedule preferences
            if let days = parseDays(from: collectedAnswers.answers(for: "schedule")) {
                profile.preferredWorkoutDays = days
            }
            if let experience = parseExperience(
                from: collectedAnswers.answers(for: "background") + collectedAnswers.answers(for: "experience")
            ) {
                profile.workoutExperience = experience
            }
            if let equipment = parseEquipment(from: collectedAnswers.answers(for: "equipment")) {
                profile.workoutEquipment = equipment
            }
            if let duration = acceptedSessionDuration(for: plan) {
                profile.workoutTimePerSession = duration
            }

            try? modelContext.save()
            HapticManager.success()
            dismiss()
        }
    }

    // MARK: - Build Request

    private func buildRequest() -> WorkoutPlanGenerationRequest {
        if isEditingExistingPlan, collectedAnswers.allAnswers().isEmpty {
            return buildEditingRequest()
        }

        let profile = userProfile

        // Parse workout types
        let workoutTypeAnswers = collectedAnswers.answers(for: "workoutType")
        let scheduleAnswers = collectedAnswers.answers(for: "schedule")
        let equipmentAnswers = collectedAnswers.answers(for: "equipment")
        let backgroundAnswers = collectedAnswers.answers(for: "background")
        let constraintAnswers = collectedAnswers.answers(for: "constraints")
        let workoutTypes = parseWorkoutTypes(from: workoutTypeAnswers)
        let primaryType: WorkoutPlanGenerationRequest.WorkoutType = workoutTypes.count == 1 ? workoutTypes.first ?? .mixed : .mixed

        // Parse other fields
        let experience = parseExperience(from: backgroundAnswers)
        let equipment = parseEquipment(from: equipmentAnswers)
        let days = parseDays(from: scheduleAnswers)
        let cardioTypes = parseCardioTypes(from: workoutTypeAnswers + constraintAnswers)
        let timePerWorkout = parseSessionDuration(
            from: workoutTypeAnswers + scheduleAnswers + equipmentAnswers + backgroundAnswers + constraintAnswers
        )

        // Custom text from non-standard answers
        let customWorkoutTypes = workoutTypeAnswers.filter { !["Strength", "Cardio", "HIIT", "Flexibility", "Mixed"].contains($0) }
        let customWorkoutType = customWorkoutTypes.isEmpty ? nil : customWorkoutTypes.joined(separator: ", ")
        let customExperience = backgroundAnswers.first { !["Beginner", "Returning", "Intermediate", "Advanced"].contains($0) }
        let customEquipment = equipmentAnswers.first { !["Full Gym", "Home - Dumbbells", "Home - Full Setup", "Bodyweight Only"].contains($0) }
        let customModalities = (workoutTypeAnswers + constraintAnswers).filter {
            !["Strength", "Cardio", "HIIT", "Flexibility", "Mixed", "Climbing", "Yoga", "Pilates", "Mobility", "Running", "Cycling", "Swimming", "Rowing", "Walking", "Jump Rope", "Need cardio included", "Let Trai decide"].contains($0)
        }
        let preferences = buildPreferenceSummary(
            scheduleAnswers: scheduleAnswers,
            backgroundAnswers: backgroundAnswers,
            constraintAnswers: constraintAnswers
        )
        let conversationContext = buildConversationContext(
            workoutTypeAnswers: workoutTypeAnswers,
            scheduleAnswers: scheduleAnswers,
            equipmentAnswers: equipmentAnswers,
            backgroundAnswers: backgroundAnswers,
            constraintAnswers: constraintAnswers
        )

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
            timePerWorkout: timePerWorkout,
            preferredSplit: nil,
            cardioTypes: cardioTypes.isEmpty ? nil : cardioTypes,
            customWorkoutType: customWorkoutType,
            customExperience: customExperience,
            customEquipment: customEquipment,
            customCardioType: customModalities.isEmpty ? nil : customModalities.joined(separator: ", "),
            specificGoals: nil,
            weakPoints: nil,
            injuries: extractLimitations(from: constraintAnswers),
            preferences: preferences,
            conversationContext: conversationContext
        )
    }

    private var refinementConversationHistory: [WorkoutPlanChatMessage] {
        messages.compactMap { message in
            switch message.type {
            case .userAnswer(let answers):
                return WorkoutPlanChatMessage(role: .user, content: answers.joined(separator: ", "))
            case .traiMessage(let text):
                return WorkoutPlanChatMessage(role: .assistant, content: text)
            case .planProposal(_, let message), .currentPlan(_, let message):
                guard !message.isEmpty else { return nil }
                return WorkoutPlanChatMessage(role: .assistant, content: message)
            case .error(let text):
                return WorkoutPlanChatMessage(role: .assistant, content: text)
            case .question(_), .thinking(_), .planAccepted, .planUpdated(_):
                return nil
            }
        }
    }

    private func buildEditingRequest() -> WorkoutPlanGenerationRequest {
        let currentPlan = generatedPlan ?? currentPlanToEdit
        let inferredWorkoutTypes = currentPlan.map { inferWorkoutTypes(from: $0) } ?? []
        let primaryWorkoutType = inferredWorkoutTypes.count == 1
            ? (inferredWorkoutTypes.first ?? .mixed)
            : .mixed
        let inferredCardioTypes = currentPlan.map { inferCardioTypes(from: $0) } ?? []
        let preferredSplit = currentPlan.flatMap { inferPreferredSplit(from: $0) }

        if let profile = userProfile {
            return profile.buildWorkoutPlanRequest(
                workoutType: primaryWorkoutType,
                selectedWorkoutTypes: inferredWorkoutTypes.isEmpty ? nil : inferredWorkoutTypes,
                preferredSplit: preferredSplit,
                cardioTypes: inferredCardioTypes.isEmpty ? nil : inferredCardioTypes,
                timePerWorkout: inferSessionDuration(from: currentPlan)
            )
        }

        return WorkoutPlanGenerationRequest(
            name: "User",
            age: 30,
            gender: .notSpecified,
            goal: .health,
            activityLevel: .moderate,
            workoutType: primaryWorkoutType,
            selectedWorkoutTypes: inferredWorkoutTypes.isEmpty ? nil : inferredWorkoutTypes,
            experienceLevel: nil,
            equipmentAccess: nil,
            availableDays: currentPlan?.daysPerWeek,
            timePerWorkout: inferSessionDuration(from: currentPlan),
            preferredSplit: preferredSplit,
            cardioTypes: inferredCardioTypes.isEmpty ? nil : inferredCardioTypes,
            customWorkoutType: nil,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: nil,
            weakPoints: nil,
            injuries: nil,
            preferences: nil,
            conversationContext: nil
        )
    }

    private func inferWorkoutTypes(from plan: WorkoutPlan) -> [WorkoutPlanGenerationRequest.WorkoutType] {
        var inferredTypes: [WorkoutPlanGenerationRequest.WorkoutType] = []

        for template in plan.templates {
            let inferredType: WorkoutPlanGenerationRequest.WorkoutType

            switch template.sessionType {
            case .strength:
                inferredType = .strength
            case .cardio, .climbing:
                inferredType = .cardio
            case .hiit:
                inferredType = .hiit
            case .yoga, .pilates, .flexibility, .mobility, .recovery:
                inferredType = .flexibility
            case .mixed, .custom:
                inferredType = .mixed
            }

            if !inferredTypes.contains(inferredType) {
                inferredTypes.append(inferredType)
            }
        }

        if inferredTypes.isEmpty, !plan.templates.isEmpty {
            return [.mixed]
        }

        return inferredTypes
    }

    private func inferPreferredSplit(from plan: WorkoutPlan) -> WorkoutPlanGenerationRequest.PreferredSplit? {
        switch plan.splitType {
        case .pushPullLegs:
            return .pushPullLegs
        case .upperLower:
            return .upperLower
        case .fullBody:
            return .fullBody
        case .bodyPartSplit:
            return .broSplit
        case .custom:
            return nil
        }
    }

    private func inferCardioTypes(from plan: WorkoutPlan) -> [WorkoutPlanGenerationRequest.CardioType] {
        var inferredTypes: [WorkoutPlanGenerationRequest.CardioType] = []

        for template in plan.templates {
            let loweredTokens = ([template.name] + template.focusAreas)
                .joined(separator: " ")
                .lowercased()

            let inferredType: WorkoutPlanGenerationRequest.CardioType?

            if template.sessionType == .climbing || loweredTokens.contains("climb") || loweredTokens.contains("boulder") {
                inferredType = .climbing
            } else if loweredTokens.contains("run") {
                inferredType = .running
            } else if loweredTokens.contains("cycl") {
                inferredType = .cycling
            } else if loweredTokens.contains("swim") {
                inferredType = .swimming
            } else if loweredTokens.contains("row") {
                inferredType = .rowing
            } else if loweredTokens.contains("walk") || loweredTokens.contains("hike") {
                inferredType = .walking
            } else if loweredTokens.contains("jump rope") || loweredTokens.contains("jumprope") {
                inferredType = .jumpRope
            } else if template.sessionType == .cardio {
                inferredType = .anyCardio
            } else {
                inferredType = nil
            }

            if let inferredType, !inferredTypes.contains(inferredType) {
                inferredTypes.append(inferredType)
            }
        }

        return inferredTypes
    }

    // MARK: - Parsing Helpers

    private func parseWorkoutTypes(from answers: [String]) -> [WorkoutPlanGenerationRequest.WorkoutType] {
        answers.compactMap { answer in
            switch answer {
            case "Strength": return .strength
            case "Cardio": return .cardio
            case "HIIT": return .hiit
            case "Yoga", "Pilates", "Mobility", "Flexibility": return .flexibility
            case "Climbing": return .cardio
            case "Mixed": return .mixed
            default: return nil
            }
        }
    }

    private func parseExperience(from answers: [String]) -> WorkoutPlanGenerationRequest.ExperienceLevel? {
        guard let answer = answers.first else { return nil }
        switch answer {
        case "Beginner": return .beginner
        case "Returning": return .intermediate
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
        let lowered = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered == "flexible" { return nil }

        let numberTokens = numericTokens(in: lowered)
        guard numberTokens.count == 1 else { return nil }
        guard lowered.contains("day")
            || lowered.contains("per week")
            || lowered.contains("/week")
            || lowered.contains("x/week")
            || lowered.contains("x week")
        else {
            return nil
        }

        let days = numberTokens[0]
        guard (1...7).contains(days) else { return nil }
        return days
    }

    private func parseCardioTypes(from answers: [String]) -> [WorkoutPlanGenerationRequest.CardioType] {
        answers.compactMap { answer in
            switch answer {
            case "Cardio", "Need cardio included": return .anyCardio
            case "Running": return .running
            case "Cycling": return .cycling
            case "Swimming": return .swimming
            case "Climbing": return .climbing
            case "Walking": return .walking
            case "Rowing": return .rowing
            case "Jump Rope": return .jumpRope
            case "Anything works": return .anyCardio
            default: return nil
            }
        }
    }

    private func parseSessionDuration(from answers: [String]) -> Int? {
        for answer in answers {
            let lowered = answer.lowercased()
            let numberTokens = numericTokens(in: lowered)
            guard numberTokens.count == 1 else { continue }
            let value = numberTokens[0]
            if lowered.contains("hour") {
                return value * 60
            }
            if lowered.contains("min") || lowered.contains("minute") {
                return value
            }
        }
        return nil
    }

    private func numericTokens(in text: String) -> [Int] {
        text.split { !$0.isNumber }.compactMap { Int($0) }
    }

    private func acceptedSessionDuration(for plan: WorkoutPlan) -> Int? {
        parseSessionDuration(
            from: collectedAnswers.answers(for: "workoutType")
                + collectedAnswers.answers(for: "schedule")
                + collectedAnswers.answers(for: "equipment")
                + collectedAnswers.answers(for: "background")
                + collectedAnswers.answers(for: "constraints")
        ) ?? inferSessionDuration(from: plan)
    }

    private func buildPreferenceSummary(
        scheduleAnswers: [String],
        backgroundAnswers: [String],
        constraintAnswers: [String]
    ) -> String? {
        var notes: [String] = []
        let customSchedule = scheduleAnswers.filter { !["2 days", "3 days", "4 days", "5 days", "Flexible"].contains($0) }
        if !customSchedule.isEmpty {
            notes.append("Schedule details: \(customSchedule.joined(separator: ", "))")
        }
        let customBackground = backgroundAnswers.filter { !["Beginner", "Returning", "Intermediate", "Advanced"].contains($0) }
        if !customBackground.isEmpty {
            notes.append("Training background: \(customBackground.joined(separator: ", "))")
        }
        let customConstraints = constraintAnswers.filter {
            !["Short sessions", "Need cardio included", "Low impact", "Want variety", "Working around an injury", "Let Trai decide"].contains($0)
        }
        if !customConstraints.isEmpty {
            notes.append("Constraints and preferences: \(customConstraints.joined(separator: ", "))")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " | ")
    }

    private func buildConversationContext(
        workoutTypeAnswers: [String],
        scheduleAnswers: [String],
        equipmentAnswers: [String],
        backgroundAnswers: [String],
        constraintAnswers: [String]
    ) -> [String]? {
        var context: [String] = []

        if !workoutTypeAnswers.isEmpty {
            context.append("Requested training styles: \(workoutTypeAnswers.joined(separator: ", "))")
        }
        if !scheduleAnswers.isEmpty {
            context.append("Schedule context: \(scheduleAnswers.joined(separator: ", "))")
        }
        if !equipmentAnswers.isEmpty {
            context.append("Equipment context: \(equipmentAnswers.joined(separator: ", "))")
        }
        if !backgroundAnswers.isEmpty {
            context.append("Training background: \(backgroundAnswers.joined(separator: ", "))")
        }
        if !constraintAnswers.isEmpty {
            context.append("Goals, constraints, or preferences: \(constraintAnswers.joined(separator: ", "))")
        }

        return context.isEmpty ? nil : context
    }

    private func extractLimitations(from answers: [String]) -> String? {
        let explicitNotes = answers.filter { answer in
            let lowered = answer.lowercased()
            return lowered.contains("injur")
                || lowered.contains("pain")
                || lowered.contains("issue")
                || lowered.contains("problem")
                || lowered.contains("bad ")
                || lowered.contains("limited")
                || lowered.contains("recover")
                || lowered.contains("can't")
                || lowered.contains("cant")
        }

        if !explicitNotes.isEmpty {
            return explicitNotes.joined(separator: ", ")
        }

        if answers.contains("Working around an injury") {
            return "Working around an injury"
        }

        if answers.contains("Low impact") {
            return "Prefers lower-impact training"
        }

        return nil
    }

    private func inferSessionDuration(from plan: WorkoutPlan?) -> Int? {
        guard let plan, !plan.templates.isEmpty else { return nil }
        let durations = plan.templates.map(\.estimatedDurationMinutes).filter { $0 > 0 }
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        return Int((Double(total) / Double(durations.count)).rounded())
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
