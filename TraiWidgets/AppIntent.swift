//
//  AppIntent.swift
//  TraiWidgets
//
//  Shared intents for widget actions
//

import AppIntents
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
