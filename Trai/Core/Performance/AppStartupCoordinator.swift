import Foundation

struct AppStartupCoordinator: Sendable {
    private(set) var didScheduleDeferredStartupWork = false
    private(set) var didScheduleStartupMigration = false
    private(set) var didScheduleFoodMemoryMaintenance = false
    private(set) var didCompleteDeferredStartupWork = false

    mutating func claimDeferredStartupWork() -> Bool {
        guard !didScheduleDeferredStartupWork else { return false }
        didScheduleDeferredStartupWork = true
        return true
    }

    mutating func claimStartupMigration() -> Bool {
        guard !didScheduleStartupMigration else { return false }
        didScheduleStartupMigration = true
        return true
    }

    mutating func claimFoodMemoryMaintenance() -> Bool {
        guard !didScheduleFoodMemoryMaintenance else { return false }
        didScheduleFoodMemoryMaintenance = true
        return true
    }

    mutating func markDeferredStartupWorkCompleted() {
        didCompleteDeferredStartupWork = true
    }

    func shouldScheduleForegroundHealthKitSync(
        hasActiveWorkoutInProgress: Bool
    ) -> Bool {
        didCompleteDeferredStartupWork && !hasActiveWorkoutInProgress
    }
}
