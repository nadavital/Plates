//
//  CoachSignal.swift
//  Trai
//
//  Short-lived coaching context signals (pain, readiness, constraints).
//

import Foundation
import SwiftData

enum CoachSignalSource: String, Codable, CaseIterable, Sendable {
    case workoutCheckIn
    case dashboardNote
    case chat
    case systemInference

    var displayName: String {
        switch self {
        case .workoutCheckIn: "Workout Check-In"
        case .dashboardNote: "Dashboard Note"
        case .chat: "Chat"
        case .systemInference: "System"
        }
    }
}

enum CoachSignalDomain: String, Codable, CaseIterable, Sendable {
    case recovery
    case pain
    case readiness
    case schedule
    case nutrition
    case sleep
    case stress
    case general

    var displayName: String {
        switch self {
        case .recovery: "Recovery"
        case .pain: "Pain"
        case .readiness: "Readiness"
        case .schedule: "Schedule"
        case .nutrition: "Nutrition"
        case .sleep: "Sleep"
        case .stress: "Stress"
        case .general: "General"
        }
    }

    var iconName: String {
        switch self {
        case .recovery: "heart.circle.fill"
        case .pain: "cross.case.fill"
        case .readiness: "gauge.with.needle"
        case .schedule: "calendar"
        case .nutrition: "fork.knife.circle.fill"
        case .sleep: "moon.zzz.fill"
        case .stress: "waveform.path.ecg"
        case .general: "circle.hexagongrid.circle"
        }
    }
}

@Model
final class CoachSignal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var expiresAt: Date = Date().addingTimeInterval(72 * 60 * 60)
    var sourceRaw: String = CoachSignalSource.systemInference.rawValue
    var domainRaw: String = CoachSignalDomain.general.rawValue
    var title: String = ""
    var detail: String = ""
    var severity: Double = 0.4
    var confidence: Double = 0.6
    var metadataJSON: String?
    var isResolved: Bool = false
    var resolvedAt: Date?
    var resolutionNote: String?

    init(
        title: String,
        detail: String,
        source: CoachSignalSource,
        domain: CoachSignalDomain,
        severity: Double = 0.4,
        confidence: Double = 0.6,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.sourceRaw = source.rawValue
        self.domainRaw = domain.rawValue
        self.severity = min(1.0, max(0.0, severity))
        self.confidence = min(1.0, max(0.0, confidence))
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(72 * 60 * 60)
        self.metadataJSON = metadataJSON
        self.isResolved = false
        self.resolvedAt = nil
        self.resolutionNote = nil
    }

    var source: CoachSignalSource {
        get { CoachSignalSource(rawValue: sourceRaw) ?? .systemInference }
        set { sourceRaw = newValue.rawValue }
    }

    var domain: CoachSignalDomain {
        get { CoachSignalDomain(rawValue: domainRaw) ?? .general }
        set { domainRaw = newValue.rawValue }
    }

    func isActive(now: Date = .now) -> Bool {
        !isResolved && expiresAt > now
    }

    func markResolved(note: String? = nil, resolvedAt: Date = .now) {
        isResolved = true
        self.resolvedAt = resolvedAt
        resolutionNote = note
    }

    var severityLabel: String {
        switch severity {
        case ..<0.34: "Low"
        case ..<0.67: "Medium"
        default: "High"
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case ..<0.34: "Low Confidence"
        case ..<0.67: "Medium Confidence"
        default: "High Confidence"
        }
    }
}

struct CoachSignalSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let source: CoachSignalSource
    let domain: CoachSignalDomain
    let title: String
    let detail: String
    let severity: Double
    let confidence: Double
}

extension CoachSignal {
    var snapshot: CoachSignalSnapshot {
        CoachSignalSnapshot(
            id: id,
            createdAt: createdAt,
            expiresAt: expiresAt,
            source: source,
            domain: domain,
            title: title,
            detail: detail,
            severity: severity,
            confidence: confidence
        )
    }
}

extension Array where Element == CoachSignal {
    func active(now: Date = .now) -> [CoachSignal] {
        filter { $0.isActive(now: now) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func activeSnapshots(now: Date = .now) -> [CoachSignalSnapshot] {
        active(now: now).map(\.snapshot)
    }

    func pulseSummary(maxCount: Int = 3, now: Date = .now) -> String {
        let activeSignals = active(now: now).prefix(maxCount)
        guard !activeSignals.isEmpty else { return "" }

        return activeSignals.map { signal in
            "\(signal.domain.displayName): \(signal.title) (\(signal.severityLabel.lowercased()))"
        }.joined(separator: "\n")
    }
}
