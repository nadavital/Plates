//
//  WorkoutGoalAISheet.swift
//  Trai
//

import SwiftUI

struct WorkoutGoalAISheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?

    let userGoal: String?
    let workoutPlan: WorkoutPlan?
    let workouts: [LiveWorkout]
    let sessions: [WorkoutSession]
    let exerciseHistory: [ExerciseHistory]
    let memoryContext: [String]
    let existingGoals: [WorkoutGoal]
    let prefersMetricWeight: Bool
    var initialSuggestions: [WorkoutGoalSuggestion] = []
    var onSuggestionsGenerated: (([WorkoutGoalSuggestion]) -> Void)? = nil
    let onSaveGoals: ([WorkoutGoal]) -> Void

    @State private var aiService = AIService()
    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var suggestions: [WorkoutGoalSuggestion] = []
    @State private var selectedSuggestionIDs: Set<String> = []
    @State private var presentedAccountSetupContext: AccountSetupContext?

    private var canAccessWorkoutGoalAI: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private var requiresAuthenticatedAccount: Bool {
        accountSessionService?.isAuthenticated != true
    }

    private var selectedGoals: [WorkoutGoal] {
        suggestions
            .filter { selectedSuggestionIDs.contains($0.id) }
            .map { $0.asWorkoutGoal() }
    }

    private var plannedSessionSummaries: [String] {
        (workoutPlan?.templates ?? []).prefix(6).map { template in
            let detail = template.focusAreasDisplay.isEmpty ? template.sessionType.displayName : template.focusAreasDisplay
            return "\(template.name) (\(template.sessionType.displayName) • \(detail))"
        }
    }

    private var recentSessionSummaries: [String] {
        WorkoutGoalRecommendationContextBuilder.recentSessionSummaries(
            workouts: workouts,
            sessions: sessions
        )
    }

    private var existingGoalTitles: [String] {
        existingGoals.map(\.trimmedTitle).filter { !$0.isEmpty }
    }

    private var hasActiveGoals: Bool {
        existingGoals.contains { $0.status == .active }
    }

    private let examplePrompts = [
        "Bench 185 for 5",
        "Climb 2x/week",
        "Send a V5 project",
        "Build to 75 min zone 2"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    promptCard
                        .traiCard(cornerRadius: 16)

                    if !canAccessWorkoutGoalAI {
                        ProUpsellInlineCard(
                            source: .workoutPlan,
                            actionTitle: "Unlock Trai Pro"
                        ) {
                            proUpsellCoordinator?.present(source: .workoutPlan)
                        }
                        .traiCard(cornerRadius: 16)
                    } else if isGenerating {
                        generatingCard
                            .traiCard(cornerRadius: 16)
                    } else if suggestions.isEmpty {
                        generateCard
                            .traiCard(cornerRadius: 16)
                    } else {
                        suggestionsCard
                            .traiCard(cornerRadius: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Set Goals with Trai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if !selectedGoals.isEmpty {
                        Button("Save", systemImage: "checkmark") {
                            onSaveGoals(selectedGoals)
                            HapticManager.success()
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                        .tint(.accentColor)
                    }
                }
            }
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
        .traiSheetBranding()
        .proUpsellPresenter()
        .onAppear {
            if suggestions.isEmpty, !initialSuggestions.isEmpty {
                suggestions = initialSuggestions
                selectedSuggestionIDs = Set(initialSuggestions.map(\.id))
                return
            }

            guard suggestions.isEmpty, !hasActiveGoals, canAccessWorkoutGoalAI else { return }
            Task { await generateSuggestions() }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set Goals with Trai")
                            .font(.traiHeadline())
                            .foregroundStyle(.white)

                        Text("Turn a route, lift, or consistency target into something Trai can track.")
                            .font(.traiLabel(12))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TraiColors.brandGradient, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("Tell Trai what you want")
                    .font(.traiHeadline(15))

                TextField("e.g. Send a V5 project or get back to 90 minute long runs", text: $promptText, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                FlowLayout(spacing: 8) {
                    ForEach(examplePrompts, id: \.self) { prompt in
                        Button(prompt) {
                            promptText = prompt
                        }
                        .font(.traiLabel(12))
                        .buttonStyle(.traiSecondary(size: .compact, fullWidth: false))
                    }
                }
            }
        }
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggestions", systemImage: "scope")
                .font(.traiHeadline())

            Text("Trai will suggest one or two goals from your plan, training, and history.")
                .font(.traiLabel(12))
                .foregroundStyle(.secondary)

            Button {
                Task { await generateSuggestions() }
            } label: {
                Label("Refresh Suggestions", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true))
        }
    }

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggestions", systemImage: "sparkles")
                .font(.traiHeadline())

            HStack(spacing: 10) {
                ProgressView()
                Text("Looking through your training...")
                    .font(.traiHeadline(15))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(TraiColors.brandAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("Suggested Goals", systemImage: "scope")
                    .font(.traiHeadline())

                Spacer()

                Button("Refresh") {
                    Task { await generateSuggestions() }
                }
                .font(.traiLabel(12))
            }

            Text("Pick one or both.")
                .font(.traiLabel(12))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    WorkoutGoalSuggestionCard(
                        suggestion: suggestion,
                        isSelected: selectedSuggestionIDs.contains(suggestion.id)
                    ) {
                        toggleSuggestion(suggestion)
                    }
                }
            }
        }
    }

    private func toggleSuggestion(_ suggestion: WorkoutGoalSuggestion) {
        if selectedSuggestionIDs.contains(suggestion.id) {
            selectedSuggestionIDs.remove(suggestion.id)
        } else {
            selectedSuggestionIDs.insert(suggestion.id)
        }
        HapticManager.selectionChanged()
    }

    private func generateSuggestions() async {
        guard canAccessWorkoutGoalAI else {
            proUpsellCoordinator?.present(source: .workoutPlan)
            return
        }

        guard !requiresAuthenticatedAccount else {
            presentedAccountSetupContext = .aiFeatures
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let generated = try await aiService.suggestWorkoutGoals(
                userGoal: userGoal,
                plannedSessions: plannedSessionSummaries,
                recentSessions: recentSessionSummaries,
                recentTrainingSummary: WorkoutGoalRecommendationContextBuilder.recentTrainingSummary(
                    workouts: workouts,
                    sessions: sessions
                ),
                exerciseSummaries: WorkoutGoalRecommendationContextBuilder.exerciseSummaries(
                    history: exerciseHistory,
                    prefersMetricWeight: prefersMetricWeight
                ),
                memoryContext: memoryContext,
                existingGoals: existingGoalTitles,
                userIntent: promptText,
                prefersMetricWeight: prefersMetricWeight
            )

            suggestions = generated
            selectedSuggestionIDs = Set(generated.map(\.id))
            onSuggestionsGenerated?(generated)
        } catch {
            print("Workout goal suggestion generation failed: \(error)")
        }
    }
}

private struct WorkoutGoalSuggestionCard: View {
    let suggestion: WorkoutGoalSuggestion
    let isSelected: Bool
    let action: () -> Void

    private var scopeLine: String {
        if let activity = suggestion.linkedActivityName, let workoutType = suggestion.linkedWorkoutType {
            return "\(workoutType.displayName) • \(activity)"
        }
        if let activity = suggestion.linkedActivityName {
            return activity
        }
        if let workoutType = suggestion.linkedWorkoutType {
            return workoutType.displayName
        }
        return "Any session"
    }

    private var targetLine: String? {
        guard suggestion.goalKind.supportsNumericTarget,
              let targetValue = suggestion.targetValue else {
            return nil
        }

        switch suggestion.goalKind {
        case .frequency:
            let unit = (suggestion.targetUnit?.isEmpty == false ? suggestion.targetUnit! : "sessions")
            let periodUnit = suggestion.periodUnit?.rawValue ?? "week"
            let periodCount = max(suggestion.periodCount ?? 1, 1)
            let periodText = periodCount == 1 ? periodUnit : "\(periodCount) \(periodUnit)s"
            return "\(Int(targetValue.rounded())) \(unit) / \(periodText)"
        case .milestone:
            return nil
        case .duration, .distance, .weight:
            let targetUnit = suggestion.targetUnit ?? ""
            guard !targetUnit.isEmpty else { return nil }
            return "\(targetValue.formatted(.number.precision(.fractionLength(0...1)))) \(targetUnit)"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: suggestion.goalKind.iconName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : TraiColors.brandAccent)
                        .frame(width: 34, height: 34)
                        .background(
                            isSelected ? Color.accentColor : TraiColors.brandAccent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.title)
                            .font(.traiHeadline(16))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(scopeLine)
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                }

                Text(suggestion.rationale)
                    .font(.traiLabel(13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let targetLine {
                    Label(targetLine, systemImage: "target")
                        .font(.traiLabel(12))
                        .foregroundStyle(.secondary)
                }

                if let targetDate = suggestion.targetDate {
                    Label("By \(targetDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                        .font(.traiLabel(12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}
