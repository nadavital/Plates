//
//  StartWorkoutIntent.swift
//  Trai
//
//  App Intent for starting a workout
//

import AppIntents
import SwiftData

/// Intent for starting a workout (opens app to workout view)
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription("Start a new workout session")

    @Parameter(title: "Workout Name", default: nil)
    var workoutName: String?

    /// This intent opens the app UI
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$workoutName) workout")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Store the workout name to start when app opens
        if let name = workoutName, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "startWorkoutFromIntent")
        } else {
            UserDefaults.standard.set("custom", forKey: "startWorkoutFromIntent")
        }

        return .result()
    }
}

// MARK: - Workout Name Entity

/// Entity for workout template names (enables Siri to suggest workouts)
struct WorkoutNameEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    static var defaultQuery = WorkoutNameQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Query for workout names from user's workout plan
struct WorkoutNameQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [WorkoutNameEntity] {
        guard let container = TraiApp.sharedModelContainer else { return [] }
        let context = container.mainContext

        let profileDescriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDescriptor).first,
              let plan = profile.workoutPlan else { return [] }

        return plan.templates
            .filter { identifiers.contains($0.id.uuidString) }
            .map { WorkoutNameEntity(id: $0.id.uuidString, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkoutNameEntity] {
        guard let container = TraiApp.sharedModelContainer else { return [] }
        let context = container.mainContext

        let profileDescriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDescriptor).first,
              let plan = profile.workoutPlan else { return [] }

        return plan.templates.map { WorkoutNameEntity(id: $0.id.uuidString, name: $0.name) }
    }

    @MainActor
    func defaultResult() async -> WorkoutNameEntity? {
        nil
    }
}
