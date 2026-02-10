//
//  AppIntent.swift
//  TraiWidgets
//
//  Shared intents for widget actions
//

import AppIntents
import Foundation
import WidgetKit

// MARK: - Open URL Intent

/// Intent to open a specific URL in the app
struct OpenURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Trai"
    static var description = IntentDescription("Opens a specific section of Trai")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "URL")
    var url: URL

    init() {
        self.url = URL(string: "trai://")!
    }

    init(_ url: URL) {
        self.url = url
    }

    func perform() async throws -> some IntentResult {
        // The URL will be handled by the app when it opens
        return .result()
    }
}

// MARK: - Live Activity Intents

/// Intent for adding a set to the current exercise from Live Activity
/// Uses App Groups to communicate with the main app
struct AddSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add Set"
    static var description = IntentDescription("Add a set to the current exercise")

    func perform() async throws -> some IntentResult {
        // Use App Groups UserDefaults to signal the action
        let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName)
        defaults?.set(Date().timeIntervalSince1970, forKey: SharedStorageKeys.AppGroup.liveActivityAddSetTimestamp)
        return .result()
    }
}

/// Intent for toggling workout pause state from Live Activity
struct TogglePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Pause"
    static var description = IntentDescription("Pause or resume the current workout")

    func perform() async throws -> some IntentResult {
        // Use App Groups UserDefaults to signal the action
        let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName)
        defaults?.set(Date().timeIntervalSince1970, forKey: SharedStorageKeys.AppGroup.liveActivityTogglePauseTimestamp)
        return .result()
    }
}

// MARK: - Quick Food Types

enum QuickFoodType: String, AppEnum, CaseIterable {
    case water = "water"
    case coffee = "coffee"
    case snack = "snack"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food Type")

    static var caseDisplayRepresentations: [QuickFoodType: DisplayRepresentation] = [
        .water: DisplayRepresentation(title: "Glass of Water", image: .init(systemName: "drop.fill")),
        .coffee: DisplayRepresentation(title: "Coffee", image: .init(systemName: "cup.and.saucer.fill")),
        .snack: DisplayRepresentation(title: "Quick Snack", image: .init(systemName: "carrot.fill")),
    ]

    var name: String {
        switch self {
        case .water: "Glass of Water"
        case .coffee: "Black Coffee"
        case .snack: "Quick Snack"
        }
    }

    var calories: Int {
        switch self {
        case .water: 0
        case .coffee: 5
        case .snack: 150
        }
    }

    var protein: Int {
        switch self {
        case .water: 0
        case .coffee: 0
        case .snack: 5
        }
    }

    var mealType: String {
        switch self {
        case .water, .coffee: "drink"
        case .snack: "snack"
        }
    }
}

// MARK: - Quick Food Logging Intent

/// Intent for logging quick food items directly from widgets
struct LogQuickFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Food"
    static var description = IntentDescription("Quickly log water, coffee, or a snack")

    @Parameter(title: "Food Type")
    var foodType: QuickFoodType

    init() {
        self.foodType = .water
    }

    init(foodType: QuickFoodType) {
        self.foodType = foodType
    }

    func perform() async throws -> some IntentResult {
        // Create pending food log
        let log = PendingFoodLog(
            name: foodType.name,
            calories: foodType.calories,
            protein: foodType.protein,
            loggedAt: Date(),
            mealType: foodType.mealType
        )

        // Save to App Groups for main app to process
        guard let defaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName) else {
            return .result()
        }

        // Load existing pending logs
        var pendingLogs: [PendingFoodLog] = []
        if let data = defaults.data(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs),
           let existing = try? JSONDecoder().decode([PendingFoodLog].self, from: data) {
            pendingLogs = existing
        }

        // Add new log
        pendingLogs.append(log)

        // Save back
        if let encoded = try? JSONEncoder().encode(pendingLogs) {
            defaults.set(encoded, forKey: SharedStorageKeys.AppGroup.pendingFoodLogs)
        }

        // Reload widgets to show updated data
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

// MARK: - Widget-Specific Food Intents (for interactive buttons)

/// Log water from widget
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Log a glass of water")

    func perform() async throws -> some IntentResult {
        let intent = LogQuickFoodIntent(foodType: .water)
        return try await intent.perform()
    }
}

/// Log coffee from widget
struct LogCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Coffee"
    static var description = IntentDescription("Log a cup of coffee")

    func perform() async throws -> some IntentResult {
        let intent = LogQuickFoodIntent(foodType: .coffee)
        return try await intent.perform()
    }
}

/// Log snack from widget
struct LogSnackIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Snack"
    static var description = IntentDescription("Log a quick snack")

    func perform() async throws -> some IntentResult {
        let intent = LogQuickFoodIntent(foodType: .snack)
        return try await intent.perform()
    }
}
