//
//  TraiPulseHeroCard.swift
//  Trai
//
//  Compact, model-managed Trai Pulse surface.
//

import Foundation
import SwiftUI

struct TraiPulseHeroCard: View {
    let context: DailyCoachContext
    let onAction: (DailyCoachAction) -> Void
    var onQuestionAnswer: ((TraiPulseQuestion, String) -> Void)?
    var onPlanProposalDecision: ((TraiPulsePlanProposal, TraiPulsePlanProposalDecision) -> Void)?
    var onQuickChat: ((String) -> Void)?
    var onPromptPresented: ((TraiPulseContentSnapshot) -> Void)?

    @AppStorage("trai_coach_tone") private var coachToneRaw: String = TraiCoachTone.encouraging.rawValue
    @AppStorage("pulse_last_question_answered_at") private var lastQuestionAnsweredAt: Double = 0
    @AppStorage("pulse_last_question_id") private var lastQuestionID: String = ""
    @AppStorage("pulse_cached_brief_v1") private var cachedPulseRaw: String = ""
    @AppStorage("pulse_last_model_refresh_at") private var lastModelRefreshAt: Double = 0

    @State private var geminiService = GeminiService()
    @State private var pulseContent: TraiPulseContentSnapshot?
    @State private var isLoadingPulse = false
    @State private var pulseError: String?

    @State private var selectedQuestionOptions: Set<String> = []
    @State private var questionSliderValue: Double = 5
    @State private var questionNote = ""
    @State private var answeredQuestionID: String?
    @State private var questionFeedback: String?
    @State private var showingCustomAnswerField = false
    @State private var lastTrackedPromptSignature: String?
    @FocusState private var isQuestionInputFocused: Bool

    private let questionCooldownSeconds: TimeInterval = 6 * 60 * 60
    private let pulseRefreshTTLSeconds: TimeInterval = 20 * 60

    private struct CachedPulseBrief: Codable {
        let surfaceType: String
        let title: String
        let message: String

        init(snapshot: TraiPulseContentSnapshot) {
            self.surfaceType = snapshot.surfaceType.rawValue
            self.title = snapshot.title
            self.message = snapshot.message
        }

        func snapshot() -> TraiPulseContentSnapshot {
            TraiPulseContentSnapshot(
                source: .modelManaged,
                surfaceType: TraiPulseSurfaceType(rawValue: surfaceType) ?? .coachNote,
                title: title,
                message: message,
                prompt: nil
            )
        }
    }

    private var coachTone: TraiCoachTone {
        TraiCoachTone(rawValue: coachToneRaw) ?? .encouraging
    }

    private var preferences: DailyCoachPreferences {
        TraiPulseAdaptivePreferences.makePreferences(context: context)
    }

    private var questionGate: (allowQuestion: Bool, blockedQuestionID: String?) {
        let now = Date().timeIntervalSince1970
        let sinceLast = now - lastQuestionAnsweredAt
        let allowQuestion = sinceLast >= questionCooldownSeconds
        let blockedID: String?
        if !lastQuestionID.isEmpty && sinceLast < 24 * 60 * 60 {
            blockedID = lastQuestionID
        } else {
            blockedID = nil
        }
        return (allowQuestion, blockedID)
    }

    private var displayedQuestion: TraiPulseQuestion? {
        guard let pulseContent else { return nil }
        guard case .question(let question) = pulseContent.prompt else { return nil }
        return question
    }

    private var refreshKey: String {
        let hour = Calendar.current.component(.hour, from: context.now)
        let adaptive = preferences
        let signalSignature = context.activeSignals.prefix(4).map { signal in
            "\(signal.id.uuidString)-\(Int(signal.createdAt.timeIntervalSince1970))"
        }.joined(separator: "|")

        let trendSignature: String
        if let trend = context.trend {
            trendSignature = "\(trend.daysSinceWorkout)-\(trend.lowProteinStreak)-\(trend.daysWithFoodLogs)-\(trend.proteinTargetHitDays)"
        } else {
            trendSignature = "none"
        }

        let patternSignature: String
        if let profile = context.patternProfile {
            patternSignature = "\(Int(profile.confidence * 100))"
        } else {
            patternSignature = "none"
        }

        return [
            String(hour),
            context.hasWorkoutToday.description,
            context.hasActiveWorkout.description,
            String(context.caloriesConsumed),
            String(context.calorieGoal),
            String(context.proteinConsumed),
            String(context.proteinGoal),
            String(context.readyMuscleCount),
            trendSignature,
            patternSignature,
            signalSignature,
            String(Int(lastQuestionAnsweredAt)),
            lastQuestionID,
            coachTone.rawValue,
            adaptive.effortMode.rawValue,
            adaptive.workoutWindow.rawValue,
            adaptive.tomorrowFocus.rawValue,
            String(adaptive.tomorrowWorkoutMinutes)
        ].joined(separator: "::")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            if let pulseContent {
                messageBlock(pulseContent)

                if answeredQuestionID != nil, answeredQuestionID == displayedQuestion?.id {
                    PulseSavedResponseView(
                        text: questionFeedback ?? "Saved. Pulse will adapt from this.",
                        style: pulseContent.surfaceType,
                        onEdit: {
                            answeredQuestionID = nil
                            questionFeedback = nil
                            showingCustomAnswerField = true
                        }
                    )
                } else {
                    promptBlock(pulseContent)
                }

                if let action = actionPrompt(for: pulseContent) {
                    VStack(spacing: 8) {
                        actionButton(action, style: pulseContent.surfaceType, compact: false)
                        quickChatButton(
                            prompt: quickChatPrompt(for: pulseContent),
                            compact: false
                        )
                    }
                } else {
                    quickChatButton(prompt: quickChatPrompt(for: pulseContent), compact: false)
                }
            } else if isLoadingPulse {
                loadingBlock
            } else {
                unavailableBlock
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            hydrateFromCacheIfNeeded()
            if let pulseContent {
                trackPromptPresentationIfNeeded(pulseContent)
            }
        }
        .task(id: refreshKey) {
            await refreshPulseContent()
        }
        .onChange(of: displayedQuestion?.id) { _, newID in
            resetQuestionState()
            guard let newID else {
                answeredQuestionID = nil
                questionFeedback = nil
                return
            }
            if answeredQuestionID != newID {
                answeredQuestionID = nil
                questionFeedback = nil
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isQuestionInputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        .onTapGesture {
            isQuestionInputFocused = false
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            TraiLensIcon(size: 20, palette: .energy)

            Text("Trai Pulse")
                .font(.headline)
                .fontWeight(.semibold)

            if isLoadingPulse {
                Text("Updating")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func messageBlock(_ content: TraiPulseContentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.caption)
                .foregroundStyle(PulseTheme.surfaceTint(content.surfaceType))
                .fixedSize(horizontal: false, vertical: true)

            Text(content.message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(PulseTheme.surfaceTint(content.surfaceType).opacity(0.45))
                .frame(width: 3)
                .offset(x: -10)
        }
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .tint(.accentColor)
            Text("Generating your pulse message...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pulse unavailable")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let pulseError, !pulseError.isEmpty {
                Text(pulseError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Retry") {
                Task {
                    await refreshPulseContent(force: true)
                }
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func promptBlock(_ content: TraiPulseContentSnapshot) -> some View {
        switch content.prompt {
        case .question(let question):
            if shouldShowQuestion(question) {
                questionSection(question, style: content.surfaceType)
            }
        case .action:
            EmptyView()
        case .planProposal(let proposal):
            planProposalSection(proposal)
        case .none:
            EmptyView()
        }
    }

    private func actionButton(_ action: DailyCoachAction, style: TraiPulseSurfaceType, compact: Bool) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: actionIconName(for: action))
                    .font(.subheadline)
                    .foregroundStyle(PulseTheme.surfaceTint(style))

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(compact ? 2 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact, let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(PulseTheme.surfaceTint(style).opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(PulseTheme.surfaceTint(style).opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func quickChatButton(prompt: String, compact: Bool) -> some View {
        Button {
            if let onQuickChat {
                onQuickChat(prompt)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(.subheadline)
                Text("Chat with Trai")
                    .fontWeight(.semibold)
                    .lineLimit(compact ? 2 : 1)
                if !compact {
                    Spacer(minLength: 0)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func actionPrompt(for content: TraiPulseContentSnapshot) -> DailyCoachAction? {
        guard case .action(let action) = content.prompt else { return nil }
        return action
    }

    private func actionIconName(for action: DailyCoachAction) -> String {
        switch action.kind {
        case .startWorkout, .startWorkoutTemplate:
            return "figure.strengthtraining.traditional"
        case .logFood, .openCalorieDetail, .openMacroDetail:
            return "fork.knife"
        case .logWeight, .openWeight:
            return "scalemass"
        case .openProfile:
            return "person.crop.circle"
        case .openWorkouts, .openWorkoutPlan:
            return "dumbbell.fill"
        case .openRecovery:
            return "heart.text.square"
        case .reviewNutritionPlan:
            return "list.bullet.clipboard"
        case .reviewWorkoutPlan:
            return "calendar.badge.clock"
        case .completeReminder:
            return "checkmark.circle"
        case .logFoodCamera:
            return "camera"
        }
    }

    @ViewBuilder
    private func questionSection(_ question: TraiPulseQuestion, style: TraiPulseSurfaceType) -> some View {
        PulsePromptContainer(prompt: question.prompt, style: style) {
            switch question.mode {
            case .singleChoice:
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(question.options) { option in
                            PulseChoiceChip(
                                title: option.title,
                                isSelected: false,
                                emphasized: true,
                                action: { submitQuestion(question, answer: option.title) }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)

                customAnswerToggle

                if showingCustomAnswerField {
                    PulseTextComposer(
                        placeholder: question.placeholder.isEmpty ? "Type your own answer" : question.placeholder,
                        text: $questionNote,
                        isFocused: $isQuestionInputFocused,
                        submitTitle: "Submit",
                        bordered: true,
                        onSubmit: { submitQuestion(question, answer: questionNote) }
                    )
                }

            case .multipleChoice:
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(question.options) { option in
                            PulseChoiceChip(
                                title: option.title,
                                isSelected: selectedQuestionOptions.contains(option.id),
                                emphasized: false,
                                action: {
                                    if selectedQuestionOptions.contains(option.id) {
                                        selectedQuestionOptions.remove(option.id)
                                    } else {
                                        selectedQuestionOptions.insert(option.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)

                Button("Save Response") {
                    let selectedTitles = question.options
                        .filter { selectedQuestionOptions.contains($0.id) }
                        .map(\.title)
                    submitQuestion(question, answer: selectedTitles.joined(separator: ", "))
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(selectedQuestionOptions.isEmpty)

                customAnswerToggle

                if showingCustomAnswerField {
                    PulseTextComposer(
                        placeholder: question.placeholder.isEmpty ? "Type your own answer" : question.placeholder,
                        text: $questionNote,
                        isFocused: $isQuestionInputFocused,
                        submitTitle: "Submit",
                        bordered: true,
                        onSubmit: { submitQuestion(question, answer: questionNote) }
                    )
                }

            case .slider(let range, let step, let unit):
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $questionSliderValue, in: range, step: step)
                        .tint(.accentColor)

                    Text("Value: \(Int(questionSliderValue.rounded()))\(unit ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    PulseTextComposer(
                        placeholder: question.placeholder.isEmpty ? "Optional note" : question.placeholder,
                        text: $questionNote,
                        isFocused: $isQuestionInputFocused,
                        submitTitle: "Save",
                        bordered: false,
                        onSubmit: {
                            var answer = "\(Int(questionSliderValue.rounded()))\(unit ?? "")"
                            let trimmedNote = questionNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedNote.isEmpty {
                                answer += " - \(trimmedNote)"
                            }
                            submitQuestion(question, answer: answer)
                        }
                    )
                }

            case .note(let maxLength):
                VStack(alignment: .leading, spacing: 8) {
                    TextField(question.placeholder.isEmpty ? "Add details" : question.placeholder, text: $questionNote, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($isQuestionInputFocused)
                        .submitLabel(.done)
                        .onSubmit { isQuestionInputFocused = false }
                        .onChange(of: questionNote) { _, newValue in
                            if newValue.count > maxLength {
                                questionNote = String(newValue.prefix(maxLength))
                            }
                        }

                    Button("Save") {
                        submitQuestion(question, answer: questionNote)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(questionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func planProposalSection(_ proposal: TraiPulsePlanProposal) -> some View {
        PulsePlanProposalView(
            proposal: proposal,
            onApply: {
                onPlanProposalDecision?(proposal, .apply)
            },
            onReview: {
                onPlanProposalDecision?(proposal, .review)
            },
            onLater: {
                onPlanProposalDecision?(proposal, .later)
            }
        )
    }

    private var customAnswerToggle: some View {
        Button(showingCustomAnswerField ? "Hide custom input" : "Type custom answer") {
            showingCustomAnswerField.toggle()
            if !showingCustomAnswerField {
                questionNote = ""
                isQuestionInputFocused = false
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func quickChatPrompt(for content: TraiPulseContentSnapshot) -> String {
        var sections: [String] = [
            "Pulse note: \(content.title). \(content.message)"
        ]

        switch content.prompt {
        case .question(let question):
            sections.append("Open check-in: \(question.prompt)")
        case .action(let action):
            sections.append("Suggested action: \(action.title)")
        case .planProposal(let proposal):
            sections.append("Plan proposal: \(proposal.title). Changes: \(proposal.changes.joined(separator: "; "))")
        case .none:
            break
        }

        sections.append("User opened Trai from Pulse. Use this as context if relevant.")
        return sections.joined(separator: " ")
    }

    private func shouldShowQuestion(_ question: TraiPulseQuestion) -> Bool {
        let now = Date().timeIntervalSince1970
        let sinceLastAnswer = now - lastQuestionAnsweredAt
        let isPostWorkoutFollowup = question.id == "readiness-post-workout"

        if !isPostWorkoutFollowup && sinceLastAnswer < questionCooldownSeconds {
            return false
        }

        if question.id == lastQuestionID && sinceLastAnswer < 24 * 60 * 60 {
            return false
        }

        return true
    }

    private func submitQuestion(_ question: TraiPulseQuestion, answer: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isQuestionInputFocused = false
        onQuestionAnswer?(question, trimmed)

        let now = Date().timeIntervalSince1970
        lastQuestionAnsweredAt = now
        lastQuestionID = question.id
        answeredQuestionID = question.id
        questionFeedback = feedbackText(for: question, answer: trimmed)

        HapticManager.selectionChanged()
        resetQuestionState()

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await refreshPulseContent(force: true)
        }
    }

    private func resetQuestionState() {
        selectedQuestionOptions = []
        questionSliderValue = 5
        questionNote = ""
        showingCustomAnswerField = false
    }

    private func feedbackText(for question: TraiPulseQuestion, answer: String) -> String {
        let interpretation = TraiPulseResponseInterpreter.interpret(question: question, answer: answer)
        return "\(interpretation.acknowledgement) \(interpretation.adaptationLine)"
    }

    private func hydrateFromCacheIfNeeded() {
        guard pulseContent == nil else { return }
        guard let data = cachedPulseRaw.data(using: .utf8),
              let cached = try? JSONDecoder().decode(CachedPulseBrief.self, from: data) else {
            return
        }
        let snapshot = cached.snapshot()
        pulseContent = snapshot
        trackPromptPresentationIfNeeded(snapshot)
    }

    private func persistPulseCache(_ snapshot: TraiPulseContentSnapshot) {
        let cached = CachedPulseBrief(snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(cached),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        cachedPulseRaw = json
    }

    @MainActor
    private func refreshPulseContent(force: Bool = false) async {
        guard !isLoadingPulse else { return }

        if !force {
            hydrateFromCacheIfNeeded()
            if lastModelRefreshAt > 0 {
                let age = Date().timeIntervalSince1970 - lastModelRefreshAt
                if age < pulseRefreshTTLSeconds {
                    return
                }
            }
        }

        isLoadingPulse = true
        pulseError = nil

        let request = GeminiService.PulseContentRequest(
            context: context,
            preferences: preferences,
            tone: coachTone,
            allowQuestion: questionGate.allowQuestion,
            blockedQuestionID: questionGate.blockedQuestionID
        )

        do {
            let generated = try await geminiService.generatePulseContent(request)
            pulseContent = generated
            trackPromptPresentationIfNeeded(generated)
            persistPulseCache(generated)
            lastModelRefreshAt = Date().timeIntervalSince1970
        } catch {
            pulseError = error.localizedDescription
            hydrateFromCacheIfNeeded()
        }

        isLoadingPulse = false
    }

    private func trackPromptPresentationIfNeeded(_ snapshot: TraiPulseContentSnapshot) {
        guard snapshot.prompt != nil else { return }
        let signature = promptTrackingSignature(for: snapshot)
        guard !signature.isEmpty else { return }
        guard signature != lastTrackedPromptSignature else { return }
        lastTrackedPromptSignature = signature
        onPromptPresented?(snapshot)
    }

    private func promptTrackingSignature(for snapshot: TraiPulseContentSnapshot) -> String {
        switch snapshot.prompt {
        case .question(let question):
            return "question:\(question.id)"
        case .action(let action):
            return "action:\(action.kind.rawValue):\(action.title)"
        case .planProposal(let proposal):
            return "proposal:\(proposal.id)"
        case .none:
            return ""
        }
    }
}

struct DashboardPulseTopGradient: View {
    private var lensColors: [Color] {
        TraiLensPalette.energy.colors
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    lensColors[0].opacity(0.34),
                    lensColors[1].opacity(0.26),
                    lensColors[2].opacity(0.20),
                    lensColors[3].opacity(0.14),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(lensColors[2].opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: 130, y: -120)

            Circle()
                .fill(lensColors[0].opacity(0.20))
                .frame(width: 260, height: 260)
                .blur(radius: 44)
                .offset(x: -130, y: -80)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(height: 420)
        .offset(y: -140)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color(.systemBackground)
        DashboardPulseTopGradient()

        TraiPulseHeroCard(
            context: DailyCoachContext(
                now: .now,
                hasWorkoutToday: false,
                hasActiveWorkout: false,
                caloriesConsumed: 1180,
                calorieGoal: 2300,
                proteinConsumed: 82,
                proteinGoal: 160,
                readyMuscleCount: 5,
                recommendedWorkoutName: "Upper Body",
                activeSignals: [],
                trend: nil,
                patternProfile: nil
            ),
            onAction: { _ in }
        )
        .padding()
    }
}
