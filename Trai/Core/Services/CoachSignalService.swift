//
//  CoachSignalService.swift
//  Trai
//
//  Persistence and lifecycle helpers for short-lived coaching signals.
//

import Foundation
import SwiftData

@MainActor
final class CoachSignalService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func addSignal(
        title: String,
        detail: String,
        source: CoachSignalSource,
        domain: CoachSignalDomain,
        severity: Double = 0.4,
        confidence: Double = 0.6,
        expiresAfter: TimeInterval = 72 * 60 * 60,
        metadata: [String: String]? = nil,
        saveImmediately: Bool = true
    ) -> CoachSignal {
        let createdAt = Date()
        let metadataJSON = encodeMetadata(metadata)
        let signal = CoachSignal(
            title: title,
            detail: detail,
            source: source,
            domain: domain,
            severity: severity,
            confidence: confidence,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(max(60, expiresAfter)),
            metadataJSON: metadataJSON
        )

        modelContext.insert(signal)
        if saveImmediately {
            try? modelContext.save()
        }
        return signal
    }

    func activeSignals(now: Date = .now, limit: Int? = nil) -> [CoachSignal] {
        let descriptor = FetchDescriptor<CoachSignal>(
            predicate: #Predicate { !$0.isResolved },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let unresolved = (try? modelContext.fetch(descriptor)) ?? []
        let active = unresolved.active(now: now)

        if let limit {
            return Array(active.prefix(limit))
        }
        return active
    }

    func resolveSignal(id: UUID, note: String? = nil, saveImmediately: Bool = true) {
        let descriptor = FetchDescriptor<CoachSignal>(
            predicate: #Predicate { $0.id == id }
        )

        guard let signal = try? modelContext.fetch(descriptor).first else { return }
        signal.markResolved(note: note)
        if saveImmediately {
            try? modelContext.save()
        }
    }

    @discardableResult
    func pruneExpiredSignals(now: Date = .now, saveImmediately: Bool = true) -> Int {
        let descriptor = FetchDescriptor<CoachSignal>(
            predicate: #Predicate { !$0.isResolved },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let unresolved = (try? modelContext.fetch(descriptor)) ?? []

        var expiredCount = 0
        for signal in unresolved where signal.expiresAt <= now {
            signal.markResolved(note: "Auto-expired", resolvedAt: now)
            expiredCount += 1
        }

        if expiredCount > 0 && saveImmediately {
            try? modelContext.save()
        }
        return expiredCount
    }

    func latestPulseContextSummary(maxCount: Int = 3, now: Date = .now) -> String {
        activeSignals(now: now, limit: maxCount).pulseSummary(maxCount: maxCount, now: now)
    }

    private func encodeMetadata(_ metadata: [String: String]?) -> String? {
        guard let metadata, !metadata.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(metadata),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
