//
//  AskTraiIntent.swift
//  Trai
//
//  App Intent for asking Trai questions via Siri
//

import AppIntents
import SwiftData

/// Intent for asking Trai AI coach questions
struct AskTraiIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Trai"
    static var description = IntentDescription("Ask Trai your AI fitness and nutrition coach a question")

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Trai \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await BillingService.shared.refreshAccessStateForImmediateUse()

        guard MonetizationService.shared.canAccessAIFeatures else {
            return .result(dialog: "Ask Trai is available with Trai Pro. Open the app to start your subscription.")
        }

        guard let container = TraiApp.sharedModelContainer else {
            return .result(dialog: "Unable to access Trai. Please open the app first.")
        }

        let context = container.mainContext

        // Get user profile for context
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profile = try? context.fetch(profileDescriptor).first

        // Get recent food entries for context
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? .distantFuture
        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let todayFood = (try? context.fetch(foodDescriptor)) ?? []

        // Build context for the shared AI service
        let aiService = AIService()

        do {
            let response = try await aiService.askQuickQuestion(
                question: question,
                userContext: buildUserContext(profile: profile, todayFood: todayFood)
            )

            // Keep response concise for Siri
            let shortResponse = response.prefix(500)
            return .result(dialog: "\(shortResponse)")
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.aiUserFacingMessage(
                fallback: "Sorry, I couldn't process that question. Please try again."
            )))
        }
    }

    private func buildUserContext(profile: UserProfile?, todayFood: [FoodEntry]) -> String {
        var context = ""

        if let profile {
            context += "User: \(profile.name), Goal: \(profile.goal.displayName)\n"
            context += "Calorie goal: \(profile.dailyCalorieGoal)\n"
        }

        context += FoodLogSummaryFormatter.promptSummary(
            for: todayFood,
            label: "Today's food log",
            maxEntries: 10
        )
        context += "\n"

        return context
    }
}

// MARK: - AI Service Extension for Quick Questions

extension AIService {
    /// Answer a quick question with minimal context (for Siri)
    func askQuickQuestion(
        question: String,
        userContext: String,
        tone: TraiCoachTone = .sharedPreference
    ) async throws -> String {
        try await performAIRequest(for: .coachChat) {
            let prompt = """
            You are Trai, a fitness and nutrition coach. Answer this question concisely (2-3 sentences max) for a voice response.
            Coach tone: \(tone.rawValue). \(tone.chatStylePrompt)
            Never refer to yourself as an AI or assistant.

            User context:
            \(userContext)

            Question: \(question)

            Give a helpful response. Be specific if you have data, otherwise give general advice.
            If the question is about what the user ate today, answer from the food log in the context above.
            Do not say they ate nothing if the context includes logged food entries.
            If you only have totals and not enough meal detail, say that clearly instead of inventing foods.
            """

            let body: [String: Any] = [
                "contents": [
                    ["parts": [["text": prompt]]]
                ],
                "generationConfig": buildGenerationConfig(thinkingLevel: .low, maxTokens: 500)
            ]

            return try await makeRequest(body: body)
        }
    }
}
