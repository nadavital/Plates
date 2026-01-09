//
//  WorkoutPlanChatView.swift
//  Plates
//
//  Chat interface for refining workout plans with Trai
//

import SwiftUI

struct WorkoutPlanChatView: View {
    @Binding var currentPlan: WorkoutPlan
    let request: WorkoutPlanGenerationRequest
    let onPlanUpdated: (WorkoutPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var geminiService = GeminiService()
    @State private var messages: [WorkoutPlanChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Initial context message
                            systemMessage

                            ForEach(messages) { message in
                                WorkoutPlanChatBubble(message: message) { plan in
                                    acceptProposedPlan(plan)
                                }
                                .id(message.id)
                            }

                            if isLoading {
                                loadingIndicator
                                    .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Suggestion chips
                suggestionChips

                // Input bar
                inputBar
            }
            .navigationTitle("Customize Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - System Message

    private var systemMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            TraiLensView(size: 32, state: .idle, palette: .energy)

            VStack(alignment: .leading, spacing: 4) {
                Text("I've created a **\(currentPlan.splitType.displayName)** plan for you with \(currentPlan.daysPerWeek) workouts per week. Tell me what you'd like to adjust - focus areas, exercises, or any limitations I should know about!")
                    .font(.subheadline)
            }

            Spacer()
        }
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SuggestionChip(text: "Focus on upper body") {
                    inputText = "I want to focus more on building my upper body"
                }
                SuggestionChip(text: "Add more leg work") {
                    inputText = "Can you add more leg exercises to my plan?"
                }
                SuggestionChip(text: "I have a bad knee") {
                    inputText = "I have a bad knee - can you adjust exercises to be low impact on my knees?"
                }
                SuggestionChip(text: "Shorter workouts") {
                    inputText = "Can you make the workouts shorter and more intense?"
                }
                SuggestionChip(text: "More compound lifts") {
                    inputText = "I prefer compound movements over isolation exercises"
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        ThinkingIndicator(activity: "Customizing your plan...")
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        SimpleChatInputBar(
            text: $inputText,
            placeholder: "Tell me about your preferences...",
            isLoading: isLoading,
            onSend: sendMessage,
            isFocused: $isInputFocused
        )
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMessage = WorkoutPlanChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await geminiService.refineWorkoutPlan(
                    currentPlan: currentPlan,
                    request: request,
                    userMessage: text,
                    conversationHistory: messages
                )

                switch response.responseType {
                case .proposePlan:
                    if let proposed = response.proposedPlan {
                        let assistantMessage = WorkoutPlanChatMessage(
                            role: .assistant,
                            content: response.message,
                            proposedPlan: proposed
                        )
                        messages.append(assistantMessage)
                        HapticManager.lightTap()
                    }

                case .planUpdate:
                    if let newPlan = response.updatedPlan {
                        let assistantMessage = WorkoutPlanChatMessage(
                            role: .assistant,
                            content: response.message,
                            updatedPlan: newPlan
                        )
                        messages.append(assistantMessage)
                        currentPlan = newPlan
                        onPlanUpdated(newPlan)
                        HapticManager.success()
                    }

                case .message:
                    let assistantMessage = WorkoutPlanChatMessage(
                        role: .assistant,
                        content: response.message
                    )
                    messages.append(assistantMessage)
                }
            } catch {
                let errorMessage = WorkoutPlanChatMessage(
                    role: .assistant,
                    content: "Sorry, I couldn't process that request. Please try again."
                )
                messages.append(errorMessage)
            }
            isLoading = false
        }
    }

    private func acceptProposedPlan(_ plan: WorkoutPlan) {
        currentPlan = plan
        onPlanUpdated(plan)
        HapticManager.success()

        let confirmMessage = WorkoutPlanChatMessage(
            role: .assistant,
            content: "I've updated your plan. Let me know if you'd like any other changes!"
        )
        messages.append(confirmMessage)
    }
}

// MARK: - Suggestion Chip

private struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Message Model

struct WorkoutPlanChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var proposedPlan: WorkoutPlan?
    var updatedPlan: WorkoutPlan?

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Chat Bubble

struct WorkoutPlanChatBubble: View {
    let message: WorkoutPlanChatMessage
    let onAcceptPlan: (WorkoutPlan) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                TraiLensView(size: 32, state: .idle, palette: .energy)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if message.role == .user {
                    // User message - bubble on right
                    userMessageContent
                } else {
                    // Assistant message - plain text on left
                    assistantMessageContent
                }

                // Proposed plan card
                if let proposed = message.proposedPlan {
                    WorkoutProposedPlanCard(plan: proposed, onAccept: { onAcceptPlan(proposed) })
                }

                // Updated plan indicator
                if message.updatedPlan != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Plan updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if message.role == .user {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var userMessageContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // User image if attached (future)
            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(.rect(cornerRadius: 18))
        }
    }

    private var assistantMessageContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Workout Proposed Plan Card

private struct WorkoutProposedPlanCard: View {
    let plan: WorkoutPlan
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: plan.splitType.iconName)
                    .foregroundStyle(.accent)
                Text(plan.splitType.displayName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("\(plan.daysPerWeek) days/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Templates preview
            ForEach(plan.templates.prefix(3)) { template in
                HStack {
                    Text(template.name)
                        .font(.caption)
                    Spacer()
                    Text("\(template.exerciseCount) exercises")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if plan.templates.count > 3 {
                Text("+\(plan.templates.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Accept button
            Button(action: onAccept) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Use This Plan")
                }
                .font(.subheadline)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var samplePlan = WorkoutPlan(
        splitType: .pushPullLegs,
        daysPerWeek: 3,
        templates: [
            WorkoutPlan.WorkoutTemplate(
                name: "Push Day",
                targetMuscleGroups: ["chest", "shoulders", "triceps"],
                exercises: [],
                estimatedDurationMinutes: 45,
                order: 0
            )
        ],
        rationale: "A balanced PPL split",
        guidelines: [],
        progressionStrategy: .defaultStrategy,
        warnings: nil
    )

    let request = WorkoutPlanGenerationRequest(
        name: "John",
        age: 25,
        gender: .male,
        goal: .buildMuscle,
        activityLevel: .moderate,
        workoutType: .strength,
        selectedWorkoutTypes: nil,
        experienceLevel: .intermediate,
        equipmentAccess: .fullGym,
        availableDays: 3,
        timePerWorkout: 45,
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

    WorkoutPlanChatView(
        currentPlan: $samplePlan,
        request: request,
        onPlanUpdated: { _ in }
    )
}
