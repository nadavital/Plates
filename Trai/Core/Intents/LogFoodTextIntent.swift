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
        guard let container = TraiApp.sharedModelContainer else {
            return .result(dialog: "Unable to access app data. Please open Trai first.")
        }

        let context = container.mainContext

        // Get user profile for nutrition context
        let profileDescriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDescriptor).first else {
            return .result(dialog: "Please complete onboarding in Trai first.")
        }

        // Use Gemini to analyze the food description
        let geminiService = GeminiService()
        do {
            let analysis = try await geminiService.analyzeFoodDescription(food)

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
            entry.inputMethod = "description"

            context.insert(entry)
            try context.save()

            // Sync to HealthKit if enabled
            if profile.syncFoodToHealthKit {
                let healthKitService = HealthKitService()
                try? await healthKitService.saveDietaryEnergy(Double(analysis.calories), date: Date())
            }

            return .result(dialog: "Logged \(analysis.name): \(analysis.calories) calories")
        } catch {
            return .result(dialog: "Couldn't analyze food. Try being more specific.")
        }
    }
}

// MARK: - Gemini Extension for Text Analysis

extension GeminiService {
    /// Analyze a text food description and return nutrition info
    func analyzeFoodDescription(_ description: String) async throws -> FoodAnalysisResult {
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
                "servingUnit": ["type": "string"]
            ],
            "required": ["name", "calories", "protein", "carbs", "fat", "servingSize", "servingUnit"]
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
            throw GeminiError.invalidResponse
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
            servingUnit: json["servingUnit"] as? String ?? "serving"
        )
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
    }
}
