//
//  LogFoodTextIntent.swift
//  Trai
//
//  App Intent for logging food via text description
//

import AppIntents
import SwiftData

/// Intent for logging food by text description using AI analysis
struct LogFoodTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food"
    static var description = IntentDescription("Log food by describing what you ate")

    @Parameter(title: "Food Description")
    var food: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$food)")
    }

    /// Determine meal type based on current time
    private func determineMealType() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "breakfast"
        case 11..<15: return "lunch"
        case 15..<21: return "dinner"
        default: return "snack"
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await BillingService.shared.refreshAccessStateForImmediateUse()

        guard MonetizationService.shared.canAccessAIFeatures else {
            return .result(dialog: "AI food logging is available with Trai Pro. Open the app to subscribe or log food manually.")
        }

        guard let container = TraiApp.sharedModelContainer else {
            return .result(dialog: "Unable to access app data. Please open Trai first.")
        }

        let context = container.mainContext

        // Get user profile for nutrition context
        let profileDescriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDescriptor).first else {
            return .result(dialog: "Please complete onboarding in Trai first.")
        }

        // Use the shared AI service to analyze the food description
        let aiService = AIService()
        do {
            let analysis = try await aiService.analyzeFoodDescription(food)
            let snapshotBuilder = FoodSnapshotBuilder()

            // Create food entry from analysis
            let entry = FoodEntry(
                name: analysis.name,
                mealType: determineMealType(),
                calories: analysis.calories,
                proteinGrams: analysis.protein,
                carbsGrams: analysis.carbs,
                fatGrams: analysis.fat
            )
            entry.fiberGrams = analysis.fiber
            entry.sugarGrams = analysis.sugar
            entry.servingSize = "\(analysis.servingSize) \(analysis.servingUnit)"
            entry.input = .appIntent
            entry.emoji = FoodEmojiResolver.resolve(preferred: analysis.emoji, foodName: analysis.name)
            entry.ensureDisplayMetadata()
            let acceptedSnapshot = snapshotBuilder.buildAcceptedSnapshot(
                from: entry,
                source: .appIntent,
                userEditedFields: ["appIntent"]
            )
            entry.setAcceptedSnapshot(acceptedSnapshot)

            context.insert(entry)
            _ = try? FoodMemoryService().resolvePendingEntries(limit: 3, modelContext: context)
            BehaviorTracker(modelContext: context).record(
                actionKey: BehaviorActionKey.logFood,
                domain: .nutrition,
                surface: .intent,
                outcome: .completed,
                relatedEntityId: entry.id,
                metadata: [
                    "source": "app_intent_text",
                    "name": analysis.name
                ],
                saveImmediately: false
            )
            try context.save()

            // Sync to HealthKit if enabled
            if profile.syncFoodToHealthKit {
                let healthKitService = HealthKitService()
                try? await healthKitService.saveDietaryEnergy(Double(analysis.calories), date: Date())
            }

            return .result(dialog: "Logged \(analysis.name): \(analysis.calories) calories")
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.aiUserFacingMessage(
                fallback: "Couldn't analyze food. Try being more specific."
            )))
        }
    }
}

// MARK: - AI Service Extension for Text Analysis

extension AIService {
    /// Analyze a text food description and return nutrition info
    func analyzeFoodDescription(_ description: String) async throws -> FoodAnalysisResult {
        try await performAIRequest(for: .foodPhotoAnalysis) {
            let prompt = """
            Analyze this food description and estimate nutrition facts:
            "\(description)"

            Return a JSON object with:
            - name: string (cleaned up food name)
            - calories: integer
            - protein: number (grams)
            - carbs: number (grams)
            - fat: number (grams)
            - fiber: number (grams, optional)
            - sugar: number (grams, optional)
            - servingSize: number
            - servingUnit: string
            - emoji: string (single relevant food emoji)

            Be reasonable with estimates based on typical serving sizes.
            """

            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "calories": ["type": "integer"],
                    "protein": ["type": "number"],
                    "carbs": ["type": "number"],
                    "fat": ["type": "number"],
                    "fiber": ["type": "number"],
                    "sugar": ["type": "number"],
                    "servingSize": ["type": "number"],
                    "servingUnit": ["type": "string"],
                    "emoji": ["type": "string"]
                ],
                "required": ["name", "calories", "protein", "carbs", "fat", "servingSize", "servingUnit", "emoji"]
            ]

            let body: [String: Any] = [
                "contents": [
                    ["parts": [["text": prompt]]]
                ],
                "generationConfig": buildGenerationConfig(
                    thinkingLevel: .low,
                    jsonSchema: schema
                )
            ]

            let response = try await makeRequest(body: body)

            guard let data = response.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIServiceError.invalidResponse
            }

            return FoodAnalysisResult(
                name: json["name"] as? String ?? description,
                calories: json["calories"] as? Int ?? 0,
                protein: json["protein"] as? Double ?? 0,
                carbs: json["carbs"] as? Double ?? 0,
                fat: json["fat"] as? Double ?? 0,
                fiber: json["fiber"] as? Double,
                sugar: json["sugar"] as? Double,
                servingSize: json["servingSize"] as? Double ?? 1,
                servingUnit: json["servingUnit"] as? String ?? "serving",
                emoji: json["emoji"] as? String
            )
        }
    }

    struct FoodAnalysisResult {
        let name: String
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let servingSize: Double
        let servingUnit: String
        let emoji: String?
    }
}
