//
//  PlanChatView.swift
//  Plates
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
                                loadingIndicator
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

                Divider()

                // Input bar
                inputBar
            }
            .navigationTitle("Adjust Your Plan")
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
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tint)
                }

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

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tint)
                }

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: isLoading
                        )
                }
            }
            .padding(.vertical, 12)

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your plan...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 20))

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .accentColor)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding()
        .background(.bar)
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

// MARK: - Chat Message Model

struct PlanChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var proposedPlan: NutritionPlan?
    var updatedPlan: NutritionPlan?
    var isProposal: Bool { proposedPlan != nil }

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Plan Chat Bubble

struct PlanChatBubble: View {
    let message: PlanChatMessage
    var onAcceptProposal: ((NutritionPlan) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tint)
                    }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? Color.accentColor
                            : Color(.secondarySystemBackground)
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(.rect(cornerRadius: 18))

                // Show proposed plan visualization
                if let proposed = message.proposedPlan {
                    ProposedPlanCard(plan: proposed) {
                        onAcceptProposal?(proposed)
                    }
                }

                // Show plan update indicator
                if message.updatedPlan != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text("Plan updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
    }
}

// MARK: - Proposed Plan Card

struct ProposedPlanCard: View {
    let plan: NutritionPlan
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("Suggested Plan", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Spacer()
            }

            // Calories - big and prominent
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(plan.dailyTargets.calories)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))

                    Text("kcal")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text("Daily Calories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Macros with full labels
            HStack(spacing: 12) {
                MacroDisplay(
                    value: plan.dailyTargets.protein,
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.carbs,
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )

                MacroDisplay(
                    value: plan.dailyTargets.fat,
                    label: "Fat",
                    color: .yellow,
                    icon: "f.circle.fill"
                )
            }

            // Macro split bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.proteinPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.carbsPercent) / 100)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(plan.macroSplit.fatPercent) / 100)
                }
            }
            .frame(height: 10)
            .clipShape(.rect(cornerRadius: 5))

            // Accept button
            Button {
                onAccept()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)

                    Text("Accept This Plan")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
        )
    }
}

struct MacroDisplay: View {
    let value: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
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
        dietaryRestrictions: [],
        additionalNotes: ""
    )

    PlanChatView(
        currentPlan: $samplePlan,
        request: sampleRequest,
        onPlanUpdated: { _ in }
    )
}
