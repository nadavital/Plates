import Foundation
import SwiftData

#if DEBUG
struct FoodRecommendationReplayReport: Sendable {
    let generatedAt: Date
    let metrics: FoodRecommendationReplayMetrics
    let sliceMetrics: [FoodRecommendationReplaySliceMetrics]
    let failedCases: [FoodRecommendationReplayFailedCase]
    let currentSnapshots: [FoodRecommendationCurrentSnapshot]

    var summaryText: String {
        """
        Food recommendation replay evaluation
        generated=\(generatedAt.formatted(date: .abbreviated, time: .standard))

        provider,cases,hit@1,hit@3,hit@5,mrr,oneOffFP,beverageDomination,completeMealCoverage,duplicates,noSuggestions,medianMs,p95Ms
        current,\(metrics.evaluatedCases),\(format(metrics.hitAt1)),\(format(metrics.hitAt3)),\(format(metrics.hitAt5)),\(format(metrics.meanReciprocalRank)),\(format(metrics.oneOffFalsePositiveRate)),\(format(metrics.beverageDominationRate)),\(format(metrics.completeMealCoverageRate)),\(format(metrics.duplicateSuggestionRate)),\(format(metrics.noSuggestionRate)),\(format(metrics.medianRuntimeMilliseconds)),\(format(metrics.p95RuntimeMilliseconds))

        provider,slice,cases,hit@1,hit@3,hit@5,mrr,oneOffFP,beverageDomination,completeMealCoverage,duplicates,noSuggestions,medianMs,p95Ms
        \(sliceSummary(provider: "current", slices: sliceMetrics))

        current snapshots
        \(currentSnapshots.map(\.summaryText).joined(separator: "\n"))

        anonymized failed cases
        \(failedCases.prefix(5).map(\.anonymizedSummary).joined(separator: " | "))
        """
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func sliceSummary(provider: String, slices: [FoodRecommendationReplaySliceMetrics]) -> String {
        slices.map { slice in
            let metrics = slice.metrics
            return "\(provider),\(slice.label),\(metrics.evaluatedCases),\(format(metrics.hitAt1)),\(format(metrics.hitAt3)),\(format(metrics.hitAt5)),\(format(metrics.meanReciprocalRank)),\(format(metrics.oneOffFalsePositiveRate)),\(format(metrics.beverageDominationRate)),\(format(metrics.completeMealCoverageRate)),\(format(metrics.duplicateSuggestionRate)),\(format(metrics.noSuggestionRate)),\(format(metrics.medianRuntimeMilliseconds)),\(format(metrics.p95RuntimeMilliseconds))"
        }.joined(separator: "\n")
    }
}

struct FoodRecommendationCurrentSnapshot: Sendable, Equatable {
    let targetDate: Date
    let titles: [String]

    var summaryText: String {
        "target=\(targetDate.formatted(date: .numeric, time: .shortened)) current=\(titles.joined(separator: " | "))"
    }
}

struct FoodRecommendationReplayService {
    private let maximumTrainingEntriesPerReplayCase = 180

    @MainActor
    func run(
        maximumCases: Int = 50,
        includeSessionContext: Bool = true,
        modelContext: ModelContext
    ) async throws -> FoodRecommendationReplayReport {
        let entries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\FoodEntry.loggedAt)])
        ).filter { $0.acceptedSnapshot != nil }
        let observations = FoodObservationBuilder().observations(from: entries)
        let config = FoodRecommendationReplayConfig(
            minimumTrainingObservations: 5,
            maximumCases: maximumCases,
            includeSessionContext: includeSessionContext
        )

        let result = try await FoodRecommendationReplayRunner().evaluate(
            observations: observations,
            entries: entries,
            memories: [],
            provider: { trainingEntries, _, now, limit, sessionID, _ in
                let state = try trainingState(
                    from: recentTrainingEntries(from: trainingEntries, before: now)
                )
                return FoodRecommendationEngine().recommendationsSync(
                    for: FoodRecommendationRequest(
                        now: now,
                        targetDate: now,
                        sessionID: sessionID,
                        limit: limit,
                        entries: state.entries,
                        memories: state.memories
                    )
                ).suggestions
            },
            config: config
        )

        let report = FoodRecommendationReplayReport(
            generatedAt: .now,
            metrics: result.metrics,
            sliceMetrics: result.debugReport.sliceMetrics,
            failedCases: result.debugReport.failedCases,
            currentSnapshots: try currentMomentSnapshots(entries: entries, modelContext: modelContext)
        )
        print(report.summaryText)
        return report
    }

    private func recentTrainingEntries(from entries: [FoodEntry], before targetDate: Date) -> [FoodEntry] {
        Array(
            entries
                .filter { $0.loggedAt < targetDate }
                .suffix(maximumTrainingEntriesPerReplayCase)
        )
    }

    @MainActor
    private func currentMomentSnapshots(
        entries: [FoodEntry],
        modelContext: ModelContext
    ) throws -> [FoodRecommendationCurrentSnapshot] {
        let memories = try modelContext.fetch(FetchDescriptor<FoodMemory>())
        let targets = targetSnapshotDates(relativeTo: .now)
        return targets.map { targetDate in
            let suggestions = FoodRecommendationEngine().recommendationsSync(
                for: FoodRecommendationRequest(
                    now: .now,
                    targetDate: targetDate,
                    sessionID: nil,
                    limit: 5,
                    entries: entries,
                    memories: memories
                )
            ).suggestions
            return FoodRecommendationCurrentSnapshot(
                targetDate: targetDate,
                titles: suggestions.map(\.title)
            )
        }
    }

    private func targetSnapshotDates(relativeTo now: Date) -> [Date] {
        let calendar = Calendar.current
        let dayStarts = [
            calendar.startOfDay(for: now),
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        ]
        let hours = [8, 12, 15, 19, 22]
        return dayStarts.flatMap { dayStart in
            hours.compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: dayStart) }
        }
    }
}

@MainActor
private func trainingState(from entries: [FoodEntry]) throws -> (context: ModelContext, entries: [FoodEntry], memories: [FoodMemory]) {
    let schema = Schema([FoodEntry.self, FoodMemory.self])
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let clonedEntries = entries.compactMap(clonedAcceptedEntry)
    for entry in clonedEntries {
        context.insert(entry)
    }
    try context.save()
    _ = try FoodMemoryService().runMaintenance(
        backfillLimit: 0,
        resolveLimit: max(clonedEntries.count, 1),
        modelContext: context
    )
    let memories = try context.fetch(FetchDescriptor<FoodMemory>())
    return (context, clonedEntries, memories)
}

private func clonedAcceptedEntry(from entry: FoodEntry) -> FoodEntry? {
    guard let snapshot = entry.acceptedSnapshot else { return nil }
    let clone = FoodEntry(
        name: entry.name,
        mealType: entry.mealType,
        calories: entry.calories,
        proteinGrams: entry.proteinGrams,
        carbsGrams: entry.carbsGrams,
        fatGrams: entry.fatGrams
    )
    clone.fiberGrams = entry.fiberGrams
    clone.sugarGrams = entry.sugarGrams
    clone.servingSize = entry.servingSize
    clone.input = entry.input
    clone.userDescription = entry.userDescription
    clone.aiAnalysis = entry.aiAnalysis
    clone.emoji = entry.emoji
    clone.loggedAt = entry.loggedAt
    clone.sessionId = entry.sessionId
    clone.sessionOrder = entry.sessionOrder
    clone.setAcceptedSnapshot(snapshot)
    return clone
}

private extension FoodRecommendationReplayFailedCase {
    var anonymizedSummary: String {
        "target=\(targetDate.formatted(date: .numeric, time: .shortened)) components=\(hiddenCanonicalComponents.joined(separator: "+")) suggestions=\(topSuggestionCanonicalComponents.prefix(3).map { $0.joined(separator: "+") }.joined(separator: ",")) reason=\(missReason)"
    }
}
#endif
