//
//  LogWeightIntent.swift
//  Trai
//
//  App Intent for logging weight
//

import AppIntents
import SwiftData

/// Intent for logging body weight
struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description = IntentDescription("Record your current weight")

    @Parameter(title: "Weight", description: "Your weight (use your preferred unit)")
    var weight: Double

    @Parameter(title: "Unit", default: "auto")
    var unit: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log weight as \(\.$weight)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = TraiApp.sharedModelContainer else {
            return .result(dialog: "Unable to access app data. Please open Trai first.")
        }

        let context = container.mainContext

        // Get user profile for unit preference
        let profileDescriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDescriptor).first else {
            return .result(dialog: "Please complete onboarding in Trai first.")
        }

        // Determine unit and convert to kg for storage
        let usesMetric = profile.usesMetricWeight
        let specifiedUnit = unit?.lowercased()

        let weightKg: Double
        let displayUnit: String

        if specifiedUnit == "kg" || specifiedUnit == "kilograms" {
            weightKg = weight
            displayUnit = "kg"
        } else if specifiedUnit == "lbs" || specifiedUnit == "lb" || specifiedUnit == "pounds" {
            weightKg = weight / 2.20462
            displayUnit = "lbs"
        } else {
            // Use user's preference
            if usesMetric {
                weightKg = weight
                displayUnit = "kg"
            } else {
                weightKg = weight / 2.20462
                displayUnit = "lbs"
            }
        }

        // Create weight entry
        let entry = WeightEntry(weightKg: weightKg)
        context.insert(entry)
        BehaviorTracker(modelContext: context).record(
            actionKey: BehaviorActionKey.logWeight,
            domain: .body,
            surface: .intent,
            outcome: .completed,
            relatedEntityId: entry.id,
            metadata: [
                "source": "app_intent",
                "unit": displayUnit
            ],
            saveImmediately: false
        )
        try context.save()

        // Sync to HealthKit if enabled
        if profile.syncWeightToHealthKit {
            let healthKitService = HealthKitService()
            try? await healthKitService.saveWeight(weightKg, date: Date())
        }

        // Format display weight
        let displayWeight = displayUnit == "kg" ? weightKg : weight
        let formattedWeight = String(format: "%.1f", displayWeight)

        return .result(dialog: "Logged weight: \(formattedWeight) \(displayUnit)")
    }
}
