//
//  PlanChatView.swift
//  Trai
//

import SwiftUI

struct PlanChatView: View {
    @Binding var currentPlan: NutritionPlan
    let request: PlanGenerationRequest
    let onPlanUpdated: (NutritionPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var geminiService = GeminiService()
    @State private var messages: [PlanChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var pendingProposal: NutritionPlan?
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
                                PlanChatBubble(message: message) { plan in
                                    acceptProposedPlan(plan)
                                }
                                .id(message.id)
                            }

                            if isLoading {
                                ThinkingIndicator(activity: "Thinking about your plan...")
                                    .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count, initial: false) { _, _ in
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading, initial: false) { _, loading in
                        if loading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                SimpleChatInputBar(
                    text: $inputText,
                    placeholder: "Ask about your plan...",
                    isLoading: isLoading,
                    onSend: sendMessage,
                    isFocused: $isInputFocused
                )
            }
            .navigationTitle("Adjust Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - System Message

    private var systemMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            TraiLensView(size: 36, state: .idle, palette: .energy)

            VStack(alignment: .leading, spacing: 8) {
                Text("Trai")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)

                Text("I've created your personalized plan with **\(currentPlan.dailyTargets.calories) calories** daily. Feel free to ask me anything or request adjustments!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMessage = PlanChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await geminiService.refinePlan(
                    currentPlan: currentPlan,
                    request: request,
                    userMessage: text,
                    conversationHistory: messages
                )

                switch response.responseType {
                case .proposePlan:
                    // AI is proposing a plan for user to accept
                    if let proposed = response.proposedPlan {
                        pendingProposal = proposed
                        let assistantMessage = PlanChatMessage(
                            role: .assistant,
                            content: response.message,
                            proposedPlan: proposed
                        )
                        messages.append(assistantMessage)
                        HapticManager.lightTap()
                    }

                case .planUpdate:
                    // AI is directly updating the plan
                    if let newPlan = response.updatedPlan {
                        let assistantMessage = PlanChatMessage(
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
                    // AI responded with just a message
                    let assistantMessage = PlanChatMessage(
                        role: .assistant,
                        content: response.message
                    )
                    messages.append(assistantMessage)
                }
            } catch {
                let errorMessage = PlanChatMessage(
                    role: .assistant,
                    content: "Sorry, I couldn't process that request. Please try again."
                )
                messages.append(errorMessage)
            }
            isLoading = false
        }
    }

    private func acceptProposedPlan(_ plan: NutritionPlan) {
        currentPlan = plan
        onPlanUpdated(plan)
        pendingProposal = nil
        HapticManager.success()
        dismiss()
    }
}

#Preview {
    @Previewable @State var samplePlan = NutritionPlan(
        dailyTargets: .init(calories: 2100, protein: 165, carbs: 210, fat: 70, fiber: 30),
        rationale: "Sample rationale",
        macroSplit: .init(proteinPercent: 30, carbsPercent: 40, fatPercent: 30),
        nutritionGuidelines: ["Guideline 1"],
        mealTimingSuggestion: "3-4 meals",
        weeklyAdjustments: nil,
        warnings: nil,
        progressInsights: nil
    )

    let sampleRequest = PlanGenerationRequest(
        name: "John",
        age: 25,
        gender: .male,
        heightCm: 180,
        weightKg: 80,
        targetWeightKg: 75,
        activityLevel: .moderate,
        activityNotes: "",
        goal: .loseWeight,
        additionalNotes: ""
    )

    PlanChatView(
        currentPlan: $samplePlan,
        request: sampleRequest,
        onPlanUpdated: { _ in }
    )
}
