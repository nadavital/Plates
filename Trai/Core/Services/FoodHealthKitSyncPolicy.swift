import Foundation

enum FoodHealthKitSyncPolicy {
    static func shouldSyncFood(profile: UserProfile?) -> Bool {
        profile?.syncFoodToHealthKit == true
    }

    static func shouldSyncFood(profiles: [UserProfile]) -> Bool {
        shouldSyncFood(profile: profiles.first)
    }
}

@MainActor
enum FoodHealthKitMacroSync {
    static func saveIfAllowed(
        _ entry: FoodEntry,
        profile: UserProfile?,
        healthKitService: HealthKitService?
    ) {
        guard FoodHealthKitSyncPolicy.shouldSyncFood(profile: profile),
              let healthKitService else {
            return
        }

        let snapshot = FoodMacroSaveSnapshot(entry: entry)
        Task {
            do {
                try await healthKitService.saveFoodMacros(
                    calories: snapshot.calories,
                    proteinGrams: snapshot.proteinGrams,
                    carbsGrams: snapshot.carbsGrams,
                    fatGrams: snapshot.fatGrams,
                    fiberGrams: snapshot.fiberGrams,
                    sugarGrams: snapshot.sugarGrams,
                    date: snapshot.loggedAt
                )
            } catch {
#if DEBUG
                print("HealthKit: failed to save food macros - \(error.localizedDescription)")
#endif
            }
        }
    }
}

private struct FoodMacroSaveSnapshot: Sendable {
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let loggedAt: Date

    init(entry: FoodEntry) {
        calories = entry.calories
        proteinGrams = entry.proteinGrams
        carbsGrams = entry.carbsGrams
        fatGrams = entry.fatGrams
        fiberGrams = entry.fiberGrams
        sugarGrams = entry.sugarGrams
        loggedAt = entry.loggedAt
    }
}

