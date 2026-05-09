//
//  PlanAssessmentState.swift
//  Trai
//
//  Models for tracking plan reassessment recommendations
//

import Foundation

// MARK: - Plan Assessment State

/// Tracks the state of plan reassessment for a user
nonisolated struct PlanAssessmentState: Codable, Sendable {
    /// When the plan was last assessed/reviewed
    var lastAssessmentDate: Date?

    /// Active recommendation trigger (if any)
    var activeRecommendation: PlanRecommendation?

    /// Dismissed recommendations (to avoid re-showing same trigger)
    var dismissedRecommendations: [DismissedRecommendation]

    /// Weight at the time the plan was created/last updated (baseline for change detection)
    var planBaselineWeightKg: Double?

    init(
        lastAssessmentDate: Date? = nil,
        activeRecommendation: PlanRecommendation? = nil,
        dismissedRecommendations: [DismissedRecommendation] = [],
        planBaselineWeightKg: Double? = nil
    ) {
        self.lastAssessmentDate = lastAssessmentDate
        self.activeRecommendation = activeRecommendation
        self.dismissedRecommendations = dismissedRecommendations
        self.planBaselineWeightKg = planBaselineWeightKg
    }
}

// MARK: - Plan Recommendation

/// A recommendation to review the nutrition plan
nonisolated struct PlanRecommendation: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    let trigger: RecommendationTrigger
    let createdAt: Date
    let details: TriggerDetails

    init(
        id: UUID = UUID(),
        trigger: RecommendationTrigger,
        createdAt: Date = Date(),
        details: TriggerDetails
    ) {
        self.id = id
        self.trigger = trigger
        self.createdAt = createdAt
        self.details = details
    }

    // MARK: - Trigger Types

    nonisolated enum RecommendationTrigger: String, Codable {
        /// User's weight has changed significantly from baseline
        case weightChange = "weight_change"

        /// User's weight hasn't changed despite consistent logging
        case weightPlateau = "weight_plateau"

        /// Plan hasn't been reviewed in a while
        case planAge = "plan_age"
    }

    // MARK: - Trigger Details

    nonisolated struct TriggerDetails: Codable, Equatable {
        // For weight change
        var weightChangeKg: Double?
        var baselineWeightKg: Double?
        var currentWeightKg: Double?

        // For plateau
        var plateauDays: Int?
        var plateauWeightKg: Double?

        // For plan age
        var daysSinceReview: Int?
        var lastReviewDate: Date?

        init(
            weightChangeKg: Double? = nil,
            baselineWeightKg: Double? = nil,
            currentWeightKg: Double? = nil,
            plateauDays: Int? = nil,
            plateauWeightKg: Double? = nil,
            daysSinceReview: Int? = nil,
            lastReviewDate: Date? = nil
        ) {
            self.weightChangeKg = weightChangeKg
            self.baselineWeightKg = baselineWeightKg
            self.currentWeightKg = currentWeightKg
            self.plateauDays = plateauDays
            self.plateauWeightKg = plateauWeightKg
            self.daysSinceReview = daysSinceReview
            self.lastReviewDate = lastReviewDate
        }
    }
}

// MARK: - Dismissed Recommendation

/// Tracks a recommendation that was dismissed by the user
nonisolated struct DismissedRecommendation: Codable, Identifiable, Sendable {
    var id: UUID
    let trigger: PlanRecommendation.RecommendationTrigger
    let dismissedAt: Date
    /// The relevant value at dismissal (weight for weight triggers, days for age trigger)
    let relevantValue: Double?

    init(
        id: UUID = UUID(),
        trigger: PlanRecommendation.RecommendationTrigger,
        dismissedAt: Date = Date(),
        relevantValue: Double? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.dismissedAt = dismissedAt
        self.relevantValue = relevantValue
    }

    /// Check if this dismissal is still relevant (prevents re-showing same trigger)
    func isStillRelevant(
        for trigger: PlanRecommendation.RecommendationTrigger,
        currentValue: Double?
    ) -> Bool {
        // Must be same trigger type
        guard self.trigger == trigger else { return false }

        // Dismissals expire after a period (7 days for weight, 14 for plan age)
        let expirationDays = trigger == .planAge ? 14 : 7
        guard let expirationDate = Calendar.current.date(
            byAdding: .day,
            value: expirationDays,
            to: dismissedAt
        ) else { return false }

        if Date() > expirationDate {
            return false
        }

        // For weight triggers, check if value has changed significantly since dismissal
        if let dismissedValue = relevantValue, let current = currentValue {
            let change = abs(current - dismissedValue)
            // 1kg change invalidates the dismissal (new situation)
            if change >= 1.0 {
                return false
            }
        }

        return true
    }
}
