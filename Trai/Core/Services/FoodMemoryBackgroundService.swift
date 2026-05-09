import Foundation
import SwiftData

/// Runs food-memory maintenance on a dedicated actor with a fresh SwiftData context.
/// UI save paths should enqueue work here instead of resolving memories on the main context.
final class FoodMemoryBackgroundService {
    static let shared = FoodMemoryBackgroundService()

    private let worker = FoodMemoryBackgroundWorker()

    private init() {}

    func scheduleMaintenance(
        modelContainer: ModelContainer,
        backfillLimit: Int,
        resolveLimit: Int,
        delay: Duration = .seconds(30)
    ) {
        Task {
            await worker.scheduleMaintenance(
                modelContainer: modelContainer,
                backfillLimit: backfillLimit,
                resolveLimit: resolveLimit,
                delay: delay
            )
        }
    }

    func scheduleResolveEntry(
        id entryID: UUID,
        modelContainer: ModelContainer,
        delay: Duration = .milliseconds(350)
    ) {
        Task {
            await worker.scheduleResolveEntry(
                id: entryID,
                modelContainer: modelContainer,
                delay: delay
            )
        }
    }

    func scheduleResolvePending(
        limit: Int,
        modelContainer: ModelContainer,
        delay: Duration = .milliseconds(350)
    ) {
        Task {
            await worker.scheduleResolvePending(
                limit: limit,
                modelContainer: modelContainer,
                delay: delay
            )
        }
    }
}

private actor FoodMemoryBackgroundWorker {
    private var pendingEntryIDs: Set<UUID> = []
    private var pendingResolveLimit = 0
    private var resolveTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?

    func scheduleResolveEntry(
        id entryID: UUID,
        modelContainer: ModelContainer,
        delay: Duration
    ) {
        pendingEntryIDs.insert(entryID)
        scheduleResolveDrain(modelContainer: modelContainer, delay: delay)
    }

    func scheduleResolvePending(
        limit: Int,
        modelContainer: ModelContainer,
        delay: Duration
    ) {
        pendingResolveLimit = max(pendingResolveLimit, limit)
        scheduleResolveDrain(modelContainer: modelContainer, delay: delay)
    }

    func scheduleMaintenance(
        modelContainer: ModelContainer,
        backfillLimit: Int,
        resolveLimit: Int,
        delay: Duration
    ) {
        maintenanceTask?.cancel()
        maintenanceTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let modelContext = ModelContext(modelContainer)
            _ = try? FoodMemoryService().runMaintenance(
                backfillLimit: backfillLimit,
                resolveLimit: resolveLimit,
                modelContext: modelContext
            )
        }
    }

    private func scheduleResolveDrain(
        modelContainer: ModelContainer,
        delay: Duration
    ) {
        resolveTask?.cancel()
        resolveTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            drainResolveQueue(modelContainer: modelContainer)
        }
    }

    private func drainResolveQueue(modelContainer: ModelContainer) {
        let entryIDs = Array(pendingEntryIDs)
        let resolveLimit = pendingResolveLimit
        pendingEntryIDs.removeAll()
        pendingResolveLimit = 0

        let modelContext = ModelContext(modelContainer)
        if !entryIDs.isEmpty {
            _ = try? FoodMemoryService().resolveEntries(
                ids: entryIDs,
                modelContext: modelContext
            )
        }
        if resolveLimit > 0 {
            _ = try? FoodMemoryService().resolvePendingEntries(
                limit: resolveLimit,
                modelContext: modelContext
            )
        }
    }
}
