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

    /// Message shown when seeding an existing/generated plan into the chat
    var existingPlanIntroMessage = "Here's your current plan. Tell me what you'd like to change and I'll revise it without making you start over."

    /// Primary action title for saving an existing/generated plan in onboarding
    var existingPlanAcceptTitle = "Save Plan"

    /// Goals generated with the onboarding plan, shown before the user saves it
    var generatedPlanGoals: [WorkoutGoal] = []

    /// Shows compact onboarding copy for the generated plan review surface
    var showsGeneratedOnboardingHeader = false

    /// Optional first refinement to send after seeding an existing generated plan
    var initialRefinementPrompt: String? = nil

    /// Called when plan is complete (onboarding mode only)
    var onComplete: ((WorkoutPlan) -> Void)?

    /// Called when the onboarding flow should save both a final plan and the generated goals that match it.
    var onCompleteWithGoals: ((WorkoutPlan, [WorkoutGoal]) -> Void)?

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
    @State private var didSubmitInitialRefinementPrompt = false
    @State private var didRefineGeneratedPlan = false
    @State private var activeGeneratedPlanGoals: [WorkoutGoal] = []
    @State private var selectedGeneratedGoal: WorkoutGoal?
    @State private var isRefiningPlan = false

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
            TraiSuggestion("Edit goals", subtitle: "Change what Trai tracks with this plan"),
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

    private enum GeneratedPlanPresentation {
        case proposal
        case current
    }

    private var generatedResultAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var generatedResultTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .bottom)),
            removal: .opacity
        )
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
                                .transition(generatedResultTransition)
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
            if shouldShowInputBar {
                inputBar
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            isInputFocused = false
        }
        .sheet(item: $selectedGeneratedGoal) { goal in
            GeneratedWorkoutGoalDetailSheet(goal: goal)
            .traiSheetBranding()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if messages.isEmpty {
                if activeGeneratedPlanGoals.isEmpty {
                    activeGeneratedPlanGoals = generatedPlanGoals
                }
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
        if showsGeneratedOnboardingHeader {
            HStack(alignment: .center, spacing: 12) {
                TraiLensView(size: 40, state: .answering, palette: .energy, breathes: false)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Here’s the plan I built")
                        .font(.headline.weight(.bold))

                    Text("Ask for changes before you save it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        } else if !isEditingExistingPlan {
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
                onAccept: isOnboarding ? nil : { acceptPlan() },
                acceptTitle: isEditingExistingPlan ? "Save Changes" : "Use This Plan",
                onCustomize: isEditingExistingPlan || showRefineMode ? nil : { enterRefineMode() },
                isCompactReview: isOnboarding
            )

        case .currentPlan(let plan, let message):
            WorkoutPlanProposalCard(
                plan: plan,
                message: message,
                onAccept: nil,
                acceptTitle: existingPlanAcceptTitle,
                onCustomize: nil,
                isCompactReview: isOnboarding
            )

        case .generatedGoals(let goals):
            generatedGoalsCard(goals)

        case .saveGeneratedPlan:
            saveGeneratedPlanButton

        case .planUpdateInProgress(let plan):
            collapsedPlanSummary(plan)

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
            .padding(.horizontal)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color(.systemBackground))
    }

    private func generatedGoalsCard(_ goals: [WorkoutGoal]) -> some View {
        VStack(alignment: .leading, spacing: isOnboarding ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.accent)

                Text(isOnboarding ? "Goals" : "Goals Trai will track")
                    .font(.subheadline.weight(.bold))

                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(goals.prefix(2), id: \.id) { goal in
                    generatedGoalRow(goal)
                }
            }
        }
        .padding(isOnboarding ? 12 : 14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
    }

    private func generatedGoalRow(_ goal: WorkoutGoal) -> some View {
        Button {
            HapticManager.lightTap()
            selectedGeneratedGoal = goal
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if isOnboarding {
                    Image(systemName: goal.goalKind.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)
                } else {
                    Image(systemName: goal.goalKind.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                }

                VStack(alignment: .leading, spacing: isOnboarding ? 1 : 3) {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isOnboarding ? 1 : 2)

                    Text(generatedGoalDetailText(goal))
                        .font(isOnboarding ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isOnboarding ? 2 : 2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, isOnboarding ? 3 : 7)
            }
            .padding(isOnboarding ? 8 : 10)
            .background(Color(.tertiarySystemFill).opacity(0.55), in: .rect(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func collapsedPlanSummary(_ plan: WorkoutPlan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Updating previous plan")
                    .font(.subheadline.weight(.semibold))

                Text("\(plan.splitType.displayName) • \(plan.templates.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var saveGeneratedPlanButton: some View {
        Button {
            savePlan()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                Text(saveGeneratedPlanTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.traiPrimary(color: .accentColor, size: .compact, fullWidth: true, height: 42))
        .accessibilityLabel(saveGeneratedPlanTitle)
    }

    private var saveGeneratedPlanTitle: String {
        let hasGoals = !deduplicatedGeneratedPlanGoals.isEmpty
        if didRefineGeneratedPlan {
            return hasGoals ? "Save Changes + Goals" : "Save Changes"
        }
        return hasGoals ? "Save Plan + Goals" : existingPlanAcceptTitle
    }

    private var shouldShowInputBar: Bool {
        !isGenerating || isRefiningPlan
    }

    private func generatedGoalDetailText(_ goal: WorkoutGoal) -> String {
        let trackingSummary = goal.trackingSummary
        let supportingSummary = goal.supportingSummary
        return [
            trackingSummary,
            goal.scopeSummary,
            supportingSummary == trackingSummary ? nil : supportingSummary,
            goal.horizonSummary
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
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
                    allowsSkipping: false,
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

        let goals = deduplicatedGeneratedPlanGoals
        Task { @MainActor in
            await presentGeneratedResultPackage(
                plan: plan,
                introText: isOnboarding ? generatedPlanIntroText(for: plan) : nil,
                planMessage: existingPlanIntroMessage,
                goals: goals,
                includeSaveAction: isOnboarding,
                presentation: .current
            )
            submitInitialRefinementPromptIfNeeded()
        }
    }

    private func generatedPlanIntroText(for plan: WorkoutPlan) -> String {
        let compactIntro = generatedIntro(from: existingPlanIntroMessage)
        if !compactIntro.isEmpty {
            return compactIntro
        }

        return "I built this as a \(plan.daysPerWeek)-day \(plan.splitType.displayName.lowercased()) plan. You can save it or tell me what to change."
    }

    private func generatedIntro(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitInitialRefinementPromptIfNeeded() {
        guard !didSubmitInitialRefinementPrompt,
              let prompt = initialRefinementPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty,
              generatedPlan != nil else { return }

        didSubmitInitialRefinementPrompt = true
        submitRefineRequest(prompt)
    }

    private func handleContinue() {
        guard !currentAnswers.isEmpty else { return }

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
                await MainActor.run {
                    generatedPlan = plan
                }
                await presentGeneratedResultPackage(
                    plan: plan,
                    introText: generatePlanIntroMessage(for: plan),
                    planMessage: "",
                    goals: [],
                    includeSaveAction: false,
                    presentation: .proposal
                )
                HapticManager.success()
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    messages.append(WorkoutPlanFlowMessage(
                        type: .error("Trai couldn't build your plan. Please try again.")
                    ))
                    isGenerating = false
                }
                HapticManager.error()
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

        didRefineGeneratedPlan = true

        // Add user message
        withAnimation(.spring(response: 0.3)) {
            messages.removeAll(where: isGeneratedPlanReviewMessage)
            messages.append(WorkoutPlanFlowMessage(type: .planUpdateInProgress(currentPlan)))
            messages.append(WorkoutPlanFlowMessage(type: .userAnswer([messageText])))
            isRefiningPlan = true
            isGenerating = true
        }

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
                let updatedPlan = response.proposedPlan ?? response.updatedPlan
                let refreshedGoals = if isOnboarding, let updatedPlan {
                    await finalGeneratedGoals(for: updatedPlan)
                } else {
                    activeGeneratedPlanGoals
                }

                await MainActor.run {
                    if let newPlan = updatedPlan {
                        messages.removeAll(where: isGeneratedPlanReviewMessage)
                        if !isOnboarding, newPlan != currentPlan {
                            messages.append(WorkoutPlanFlowMessage(type: .planUpdated(newPlan)))
                        }
                        generatedPlan = newPlan
                        activeGeneratedPlanGoals = refreshedGoals
                    } else {
                        messages.removeAll(where: isGeneratedPlanReviewMessage)
                        messages.append(WorkoutPlanFlowMessage(
                            type: .traiMessage(response.message)
                        ))
                        isRefiningPlan = false
                        isGenerating = false
                    }
                }

                if let newPlan = updatedPlan {
                    await presentGeneratedResultPackage(
                        plan: newPlan,
                        introText: isOnboarding ? (response.message.isEmpty ? "I updated the plan and goals. Review the changes, then save when it looks right." : response.message) : nil,
                        planMessage: response.message,
                        goals: isOnboarding ? refreshedGoals : [],
                        includeSaveAction: isOnboarding,
                        presentation: .proposal
                    )
                }
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    messages.removeAll(where: isGeneratedPlanReviewMessage)
                    messages.append(WorkoutPlanFlowMessage(
                        type: .error("Trai couldn't update your plan. Please try again.")
                    ))
                    isRefiningPlan = false
                    isGenerating = false
                }
                HapticManager.error()
            }
        }
    }

    @MainActor
    private func presentGeneratedResultPackage(
        plan: WorkoutPlan,
        introText: String?,
        planMessage: String,
        goals: [WorkoutGoal],
        includeSaveAction: Bool,
        presentation: GeneratedPlanPresentation
    ) async {
        withAnimation(generatedResultAnimation) {
            isRefiningPlan = false
            isGenerating = false
        }

        if let introText, !introText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appendGeneratedResultMessage(.traiMessage(introText), delayMilliseconds: 90)
        }

        let planMessageType: WorkoutPlanFlowMessage.MessageType = switch presentation {
        case .proposal:
            .planProposal(plan, planMessage)
        case .current:
            .currentPlan(plan, planMessage)
        }
        await appendGeneratedResultMessage(planMessageType, delayMilliseconds: 130)

        let goalsToShow = goals
        if !goalsToShow.isEmpty {
            activeGeneratedPlanGoals = goalsToShow
            await appendGeneratedResultMessage(.generatedGoals(goalsToShow), delayMilliseconds: 120)
        }

        if includeSaveAction {
            await appendGeneratedResultMessage(.saveGeneratedPlan, delayMilliseconds: 90)
        }
    }

    @MainActor
    private func appendGeneratedResultMessage(
        _ type: WorkoutPlanFlowMessage.MessageType,
        delayMilliseconds: UInt64
    ) async {
        if delayMilliseconds > 0 {
            try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
        }

        withAnimation(generatedResultAnimation) {
            messages.append(WorkoutPlanFlowMessage(type: type))
        }
    }

    private func isGeneratedPlanReviewMessage(_ message: WorkoutPlanFlowMessage) -> Bool {
        switch message.type {
        case .planProposal, .currentPlan, .generatedGoals, .saveGeneratedPlan, .planUpdateInProgress:
            true
        case .question, .userAnswer, .thinking, .planAccepted, .traiMessage, .planUpdated, .error:
            false
        }
    }

    private func savePlan() {
        guard let plan = generatedPlan else { return }

        if isOnboarding {
            saveOnboardingPlan(plan)
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

    private func saveOnboardingPlan(_ plan: WorkoutPlan) {
        guard !isGenerating else { return }
        isGenerating = true

        Task {
            let goals = await finalGeneratedGoals(for: plan)
            await MainActor.run {
                activeGeneratedPlanGoals = goals
                isGenerating = false
                HapticManager.success()
                if let onCompleteWithGoals {
                    onCompleteWithGoals(plan, goals)
                } else {
                    onComplete?(plan)
                }
            }
        }
    }

    private func finalGeneratedGoals(for plan: WorkoutPlan) async -> [WorkoutGoal] {
        let currentGoals = deduplicatedGeneratedPlanGoals
        guard didRefineGeneratedPlan || currentGoals.isEmpty else {
            return currentGoals
        }

        do {
            let service = AIService()
            let suggestions = try await service.suggestWorkoutGoals(
                userGoal: userProfile?.goal.displayName,
                plannedSessions: plannedSessionSummaries(for: plan),
                recentSessions: [],
                recentTrainingSummary: [],
                exerciseSummaries: [],
                memoryContext: workoutPlanContextForAI(),
                existingGoals: activeWorkoutGoalContextForAI(),
                userIntent: latestUserRefinementIntent,
                prefersMetricWeight: userProfile?.usesMetricExerciseWeight ?? true
            )
            let goals = deduplicatedGoals(suggestions.map { $0.asWorkoutGoal() })
            return goals.isEmpty ? currentGoals : goals
        } catch {
            return currentGoals
        }
    }

    private func plannedSessionSummaries(for plan: WorkoutPlan) -> [String] {
        plan.templates.prefix(6).map { template in
            let detail = [
                template.sessionType.displayName,
                template.focusAreasDisplay,
                template.primaryBlockSummary,
                template.structuredExercises.prefix(3).map(\.exerciseName).joined(separator: ", ")
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
            return "\(template.name) (\(detail))"
        }
    }

    private var latestUserRefinementIntent: String? {
        let userMessages = refinementConversationHistory
            .filter { $0.role == .user }
            .suffix(4)
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !userMessages.isEmpty else { return nil }
        return userMessages.joined(separator: " | ")
    }

    private func deduplicatedGoals(_ goals: [WorkoutGoal]) -> [WorkoutGoal] {
        var seen: Set<String> = []
        return goals.filter { goal in
            let key = goal.planSetupDeduplicationKey
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
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
        let conversationContext = (buildConversationContext(
            workoutTypeAnswers: workoutTypeAnswers,
            scheduleAnswers: scheduleAnswers,
            equipmentAnswers: equipmentAnswers,
            backgroundAnswers: backgroundAnswers,
            constraintAnswers: constraintAnswers
        ) ?? []) + workoutPlanContextForAI()
        let specificGoals = activeWorkoutGoalContextForAI() + generatedWorkoutGoalContextForAI()

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
            specificGoals: specificGoals.isEmpty ? nil : specificGoals,
            weakPoints: nil,
            injuries: extractLimitations(from: constraintAnswers),
            preferences: preferences,
            conversationContext: conversationContext.isEmpty ? nil : conversationContext
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
            case .question(_), .thinking(_), .generatedGoals(_), .saveGeneratedPlan, .planUpdateInProgress(_), .planAccepted, .planUpdated(_):
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
        let activeGoals = activeWorkoutGoalContextForAI() + generatedWorkoutGoalContextForAI()
        let context = workoutPlanContextForAI()

        if let profile = userProfile {
            return profile.buildWorkoutPlanRequest(
                workoutType: primaryWorkoutType,
                selectedWorkoutTypes: inferredWorkoutTypes.isEmpty ? nil : inferredWorkoutTypes,
                preferredSplit: preferredSplit,
                cardioTypes: inferredCardioTypes.isEmpty ? nil : inferredCardioTypes,
                timePerWorkout: inferSessionDuration(from: currentPlan),
                specificGoals: activeGoals.isEmpty ? nil : activeGoals,
                conversationContext: context.isEmpty ? nil : context
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
            specificGoals: activeGoals.isEmpty ? nil : activeGoals,
            weakPoints: nil,
            injuries: nil,
            preferences: nil,
            conversationContext: context.isEmpty ? nil : context
        )
    }

    private func workoutPlanContextForAI() -> [String] {
        var context = OnboardingWorkoutPlanUserContext.nutritionContext(from: userProfile)
        context.append(contentsOf: workoutPlanMemoryContext())
        context.append(contentsOf: activeWorkoutGoalContextForAI().map { "Existing workout goal: \($0)" })
        context.append(contentsOf: generatedWorkoutGoalContextForAI().map { "Generated onboarding workout goal: \($0)" })
        return context
    }

    private func workoutPlanMemoryContext() -> [String] {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate<CoachMemory> { memory in
                memory.isActive
            },
            sortBy: [
                SortDescriptor(\CoachMemory.importance, order: .reverse),
                SortDescriptor(\CoachMemory.createdAt, order: .reverse)
            ]
        )
        let memories = (try? modelContext.fetch(descriptor)) ?? []
        return memories
            .filter {
                $0.topic == .workout || $0.topic == .general || $0.category == .goal || $0.category == .context || $0.category == .restriction
            }
            .prefix(8)
            .map(\.promptFormat)
    }

    private func activeWorkoutGoalContextForAI() -> [String] {
        let descriptor = FetchDescriptor<WorkoutGoal>(
            predicate: #Predicate<WorkoutGoal> { goal in
                goal.statusRaw == "active"
            },
            sortBy: [SortDescriptor(\WorkoutGoal.updatedAt, order: .reverse)]
        )
        let goals = (try? modelContext.fetch(descriptor)) ?? []
        return OnboardingWorkoutPlanUserContext.activeGoalContext(from: goals)
    }

    private func generatedWorkoutGoalContextForAI() -> [String] {
        deduplicatedGeneratedPlanGoals
            .prefix(6)
            .map { goal in
                let trackingSummary = goal.trackingSummary
                let supportingSummary = goal.supportingSummary
                return [
                    goal.title,
                    trackingSummary,
                    goal.scopeSummary,
                    supportingSummary == trackingSummary ? nil : supportingSummary,
                    goal.horizonSummary
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            }
    }

    private var deduplicatedGeneratedPlanGoals: [WorkoutGoal] {
        var seen: Set<String> = []
        return activeGeneratedPlanGoals.filter { goal in
            let key = goal.planSetupDeduplicationKey
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
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

private extension WorkoutGoal {
    var planSetupDeduplicationKey: String {
        let combinedText = [
            title,
            successCriteria,
            notes,
            linkedActivityName ?? "",
            linkedWorkoutTypeRaw ?? ""
        ]
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .lowercased()

        if combinedText.contains("session"),
           combinedText.contains("week"),
           combinedText.contains("complete") || combinedText.contains("hit") || combinedText.contains("scheduled") {
            return "plan-adherence|\(linkedWorkoutTypeRaw ?? "any")|\(periodUnitRaw ?? "week")|\(periodCount ?? 1)"
        }

        if combinedText.contains("cardio"),
           combinedText.contains("push day") || combinedText.contains("finisher") {
            return "cardio-placement|\(linkedWorkoutTypeRaw ?? "any")|\(periodUnitRaw ?? "week")|\(periodCount ?? 1)"
        }

        if goalKind == .frequency {
            return [
                goalKind.rawValue,
                linkedWorkoutTypeRaw ?? "any",
                linkedActivityName?.goalNormalizedKey ?? "",
                targetValue.map { String(Int($0.rounded())) } ?? "",
                targetUnit.goalNormalizedKey,
                periodUnitRaw ?? "",
                periodCount.map(String.init) ?? ""
            ].joined(separator: "|")
        }

        return title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}

private struct GeneratedWorkoutGoalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let goal: WorkoutGoal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    detailCard
                }
                .padding()
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .tint(.accentColor)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: goal.goalKind.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let trackingSummary = goal.trackingSummary {
                        Text(trackingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !goal.trimmedSuccessCriteria.isEmpty {
                goalDetailRow(
                    title: "How Trai verifies it",
                    value: goal.trimmedSuccessCriteria,
                    icon: "checkmark.seal.fill"
                )
            }

            if let supportingSummary = goal.supportingSummary, supportingSummary != goal.trimmedSuccessCriteria {
                goalDetailRow(
                    title: "Notes",
                    value: supportingSummary,
                    icon: "text.bubble.fill"
                )
            }

            goalDetailRow(
                title: "Scope",
                value: goal.scopeSummary,
                icon: "scope"
            )

            if let horizonSummary = goal.horizonSummary, !horizonSummary.isEmpty {
                goalDetailRow(
                    title: "Timeline",
                    value: horizonSummary,
                    icon: "calendar"
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func goalDetailRow(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

// MARK: - Preview

#Preview {
    WorkoutPlanChatFlow()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
