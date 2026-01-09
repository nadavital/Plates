//
//  WorkoutPlanConversationStep.swift
//  Plates
//
//  Conversational step where Trai asks follow-up questions
//

import SwiftUI

struct ConversationStepView: View {
    @Binding var specificGoals: [String]
    @Binding var weakPoints: [String]
    @Binding var injuries: String
    @Binding var preferences: String

    let workoutTypes: Set<WorkoutPlanGenerationRequest.WorkoutType>
    let onComplete: () -> Void

    /// Primary workout type for suggestions (uses first or .mixed)
    private var primaryWorkoutType: WorkoutPlanGenerationRequest.WorkoutType {
        if workoutTypes.count == 1, let single = workoutTypes.first {
            return single
        }
        return .mixed
    }

    @State private var currentQuestion: TraiQuestion = .specificGoals
    @State private var customInput: String = ""
    @State private var headerVisible = false
    @State private var contentVisible = false
    @FocusState private var isInputFocused: Bool

    enum TraiQuestion: CaseIterable {
        case specificGoals
        case weakPoints
        case injuries
        case preferences

        var questionText: String {
            switch self {
            case .specificGoals:
                return "Do you have any specific goals you're working towards?"
            case .weakPoints:
                return "Any areas you feel are weak or want to focus on?"
            case .injuries:
                return "Any injuries or limitations I should know about?"
            case .preferences:
                return "Anything else? Exercises you love or hate?"
            }
        }

        var placeholder: String {
            switch self {
            case .specificGoals:
                return "Type your goal or tap a suggestion..."
            case .weakPoints:
                return "Type a weak point or tap a suggestion..."
            case .injuries:
                return "Describe any injuries or limitations..."
            case .preferences:
                return "Tell me what you enjoy or want to avoid..."
            }
        }

        func suggestedAnswers(for workoutType: WorkoutPlanGenerationRequest.WorkoutType) -> [String] {
            switch self {
            case .specificGoals:
                switch workoutType {
                case .strength, .mixed:
                    return ["Do a pull-up", "Bench my bodyweight", "See my abs", "Get stronger overall", "Build muscle", "No specific goal"]
                case .cardio:
                    return ["Run a 5K", "Run a marathon", "Improve endurance", "Get faster", "No specific goal"]
                case .hiit:
                    return ["Lose body fat", "Improve conditioning", "Get more athletic", "No specific goal"]
                case .flexibility:
                    return ["Touch my toes", "Do the splits", "Reduce back pain", "Improve mobility", "No specific goal"]
                }
            case .weakPoints:
                switch workoutType {
                case .strength, .mixed:
                    return ["Weak shoulders", "Small arms", "Lagging legs", "Weak core", "Poor posture", "Nothing specific"]
                case .cardio:
                    return ["Poor endurance", "Slow pace", "Get winded easily", "Nothing specific"]
                case .hiit:
                    return ["Low stamina", "Weak core", "Poor recovery", "Nothing specific"]
                case .flexibility:
                    return ["Tight hips", "Stiff back", "Tight hamstrings", "Nothing specific"]
                }
            case .injuries:
                return ["Bad knee", "Lower back issues", "Shoulder problem", "Wrist pain", "No injuries"]
            case .preferences:
                switch workoutType {
                case .strength, .mixed:
                    return ["Love deadlifts", "Hate leg day", "Prefer dumbbells", "Love compound lifts", "No preference"]
                case .cardio:
                    return ["Love running", "Prefer outdoors", "Like variety", "Hate treadmills", "No preference"]
                case .hiit:
                    return ["Love burpees", "Hate burpees", "Like variety", "No preference"]
                case .flexibility:
                    return ["Love yoga", "Prefer stretching", "Like guided sessions", "No preference"]
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    traiHeader
                        .opacity(headerVisible ? 1 : 0)
                        .offset(y: headerVisible ? 0 : -20)
                        .padding(.top, 20)

                    // Current question
                    questionCard
                        .opacity(contentVisible ? 1 : 0)
                        .offset(y: contentVisible ? 0 : 30)

                    // Previous answers summary
                    if hasAnyAnswers {
                        answersSummary
                            .opacity(contentVisible ? 1 : 0)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            // Input bar
            inputBar
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                contentVisible = true
            }
        }
    }

    // MARK: - Trai Header

    private var traiHeader: some View {
        HStack(spacing: 12) {
            // Use TraiLens for consistent visual identity
            TraiLensView(state: .idle, palette: .energy)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text("Trai")
                    .font(.headline)
                    .foregroundStyle(.accent)

                Text("A few quick questions to personalize your plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Question Card

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question text
            Text(currentQuestion.questionText)
                .font(.title3)
                .fontWeight(.semibold)

            // Suggestion chips
            FlowLayout(spacing: 8) {
                ForEach(currentQuestion.suggestedAnswers(for: primaryWorkoutType), id: \.self) { suggestion in
                    SuggestionChipButton(text: suggestion) {
                        handleSuggestionTap(suggestion)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Answers Summary

    private var hasAnyAnswers: Bool {
        !specificGoals.isEmpty || !weakPoints.isEmpty || !injuries.isEmpty || !preferences.isEmpty
    }

    private var answersSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your answers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !specificGoals.isEmpty {
                AnswerRow(label: "Goals", values: specificGoals)
            }

            if !weakPoints.isEmpty {
                AnswerRow(label: "Focus areas", values: weakPoints)
            }

            if !injuries.isEmpty {
                AnswerRow(label: "Limitations", values: [injuries])
            }

            if !preferences.isEmpty {
                AnswerRow(label: "Preferences", values: [preferences])
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Input Bar

    private var canSend: Bool {
        !customInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 10) {
                // Text input
                TextField(currentQuestion.placeholder, text: $customInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 20))
                    .onSubmit {
                        if canSend {
                            handleCustomInput()
                        }
                    }

                // Send or Skip/Generate button
                if canSend {
                    Button {
                        handleCustomInput()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.tint(.accent).interactive(), in: .circle)
                } else {
                    Button {
                        if currentQuestion == .preferences {
                            onComplete()
                        } else {
                            moveToNextQuestion()
                        }
                    } label: {
                        Text(currentQuestion == .preferences ? "Generate" : "Skip")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .glassEffect(
                        .regular.tint(currentQuestion == .preferences ? .accent : .gray).interactive(),
                        in: .capsule
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    // MARK: - Actions

    private func handleSuggestionTap(_ suggestion: String) {
        HapticManager.lightTap()

        // Check for "skip" type answers
        let skipAnswers = ["No specific goal", "Nothing specific", "No injuries", "No preference"]
        if skipAnswers.contains(suggestion) {
            moveToNextQuestion()
            return
        }

        // Add the answer
        withAnimation(.spring(response: 0.3)) {
            switch currentQuestion {
            case .specificGoals:
                if !specificGoals.contains(suggestion) {
                    specificGoals.append(suggestion)
                }
            case .weakPoints:
                if !weakPoints.contains(suggestion) {
                    weakPoints.append(suggestion)
                }
            case .injuries:
                injuries = suggestion
            case .preferences:
                preferences = suggestion
            }
        }

        // Auto-advance for single-answer questions
        if currentQuestion == .injuries || currentQuestion == .preferences {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if currentQuestion == .preferences {
                    onComplete()
                } else {
                    moveToNextQuestion()
                }
            }
        }
    }

    private func handleCustomInput() {
        guard !customInput.isEmpty else { return }
        HapticManager.lightTap()

        withAnimation(.spring(response: 0.3)) {
            switch currentQuestion {
            case .specificGoals:
                specificGoals.append(customInput)
            case .weakPoints:
                weakPoints.append(customInput)
            case .injuries:
                injuries = customInput
            case .preferences:
                preferences = customInput
            }
        }

        customInput = ""
        isInputFocused = false

        // Move to next after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentQuestion == .preferences {
                onComplete()
            } else {
                moveToNextQuestion()
            }
        }
    }

    private func moveToNextQuestion() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch currentQuestion {
            case .specificGoals:
                currentQuestion = .weakPoints
            case .weakPoints:
                currentQuestion = .injuries
            case .injuries:
                currentQuestion = .preferences
            case .preferences:
                onComplete()
            }
        }
    }
}

// MARK: - Suggestion Chip Button

private struct SuggestionChipButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Answer Row

private struct AnswerRow: View {
    let label: String
    let values: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(values.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    ConversationStepView(
        specificGoals: .constant([]),
        weakPoints: .constant([]),
        injuries: .constant(""),
        preferences: .constant(""),
        workoutTypes: [.strength],
        onComplete: {}
    )
}
