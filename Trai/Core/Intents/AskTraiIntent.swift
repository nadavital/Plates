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
        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= startOfDay },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let todayFood = (try? context.fetch(foodDescriptor)) ?? []

        // Build context for Gemini
        let geminiService = GeminiService()

        do {
            let response = try await geminiService.askQuickQuestion(
                question: question,
                userContext: buildUserContext(profile: profile, todayFood: todayFood)
            )

            // Keep response concise for Siri
            let shortResponse = response.prefix(500)
            return .result(dialog: "\(shortResponse)")
        } catch {
            return .result(dialog: "Sorry, I couldn't process that question. Please try again.")
        }
    }

    private func buildUserContext(profile: UserProfile?, todayFood: [FoodEntry]) -> String {
        var context = ""

        if let profile {
            context += "User: \(profile.name), Goal: \(profile.goal.displayName)\n"
            context += "Calorie goal: \(profile.dailyCalorieGoal)\n"
        }

        if !todayFood.isEmpty {
            let totalCals = todayFood.reduce(0) { $0 + $1.calories }
            let totalProtein = todayFood.reduce(0) { $0 + $1.proteinGrams }
            context += "Today's intake: \(totalCals) calories, \(Int(totalProtein))g protein\n"
        }

        return context
    }
}

// MARK: - Gemini Extension for Quick Questions

extension GeminiService {
    /// Answer a quick question with minimal context (for Siri)
    func askQuickQuestion(question: String, userContext: String) async throws -> String {
        let prompt = """
        You are Trai, a friendly AI fitness and nutrition coach. Answer this question concisely (2-3 sentences max) for a voice response.

        User context:
        \(userContext)

        Question: \(question)

        Give a helpful, encouraging response. Be specific if you have data, otherwise give general advice.
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
