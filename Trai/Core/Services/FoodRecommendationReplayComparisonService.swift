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
                return FoodRecommendationEngine().recommendationsSync(
                    for: FoodRecommendationRequest(
                        now: now,
                        targetDate: now,
                        sessionID: sessionID,
                        limit: limit,
                        entries: trainingEntries,
                        memories: []
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

private extension FoodRecommendationReplayFailedCase {
    var anonymizedSummary: String {
        "target=\(targetDate.formatted(date: .numeric, time: .shortened)) components=\(hiddenCanonicalComponents.joined(separator: "+")) suggestions=\(topSuggestionCanonicalComponents.prefix(3).map { $0.joined(separator: "+") }.joined(separator: ",")) reason=\(missReason)"
    }
}
#endif
