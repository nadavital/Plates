//
//  WorkoutGoalCheckInView.swift
//  Trai
//

import SwiftUI
import SwiftData

struct GoalCheckInMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role { case user, assistant }
}

struct WorkoutGoalCheckInView: View {
    @Bindable var goal: WorkoutGoal
    let insight: WorkoutGoalInsight
    let workouts: [LiveWorkout]
    let sessions: [WorkoutSession]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var messages: [GoalCheckInMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var aiService = AIService()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            contextHeaderCard

                            ForEach(messages) { message in
                                CheckInBubble(message: message)
                                    .id(message.id)
                            }

                            if isLoading {
                                ThinkingIndicator(activity: "Trai is thinking...")
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

                SimpleChatInputBar(
                    text: $inputText,
                    placeholder: "How's it going with this goal?",
                    isLoading: isLoading,
                    onSend: sendMessage,
                    isFocused: $isInputFocused
                )
            }
            .traiBackground()
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }

                if let lastText = messages.last(where: { $0.role == .assistant })?.text {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Save Note") {
                            saveNote(lastText)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .onAppear {
            goal.markCheckedIn()
        }
    }

    private var contextHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: goal.goalKind.iconName)
                    .font(.headline)
                    .foregroundStyle(goal.status == .completed ? .green : TraiColors.flame)
                    .frame(width: 36, height: 36)
                    .background(
                        (goal.status == .completed ? Color.green : TraiColors.flame).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.trimmedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(insight.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let progressFraction = insight.progressFraction {
                ProgressView(value: progressFraction)
                    .tint(goal.status == .completed ? .green : TraiColors.flame)
            }

            Text("Tell Trai how the goal is going — recent wins, blockers, or changes to the plan.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .traiCard(glow: .activity)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }

        messages.append(GoalCheckInMessage(role: .user, text: text))
        inputText = ""
        isLoading = true

        let history = messages.dropLast().map { (role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        let recentSummaries = WorkoutGoalRecommendationContextBuilder.recentSessionSummaries(
            workouts: workouts,
            sessions: sessions
        )

        Task {
            defer { isLoading = false }
            do {
                let reply = try await aiService.checkInOnGoal(
                    goalTitle: goal.trimmedTitle,
                    goalKind: goal.goalKind.rawValue,
                    goalScope: goal.scopeSummary,
                    currentProgress: insight.currentValueText,
                    targetSummary: insight.targetValueText,
                    recentSessionSummaries: recentSummaries,
                    userMessage: text,
                    conversationHistory: history
                )
                messages.append(GoalCheckInMessage(role: .assistant, text: reply))
                HapticManager.lightTap()
            } catch {
                messages.append(GoalCheckInMessage(
                    role: .assistant,
                    text: "Sorry, I couldn't connect. Try again in a moment."
                ))
                HapticManager.error()
            }
        }
    }

    private func saveNote(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            dismiss()
            return
        }

        let checkInLabel = "Check-in (\(Date().formatted(date: .abbreviated, time: .omitted)))"
        let checkInEntry = "\(checkInLabel): \(trimmedText)"
        let existingNotes = goal.trimmedNotes
        goal.notes = existingNotes.isEmpty ? checkInEntry : "\(existingNotes)\n\n\(checkInEntry)"
        goal.updatedAt = Date()
        try? modelContext.save()
        HapticManager.success()
        dismiss()
    }
}

private struct CheckInBubble: View {
    let message: GoalCheckInMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? TraiColors.brandAccent : Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
