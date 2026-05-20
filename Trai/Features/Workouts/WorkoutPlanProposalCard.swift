//
//  WorkoutPlanProposalCard.swift
//  Trai
//
//  Inline card showing a generated workout plan with accept/customize options
//

import SwiftUI

/// Card displayed inline in chat showing the generated workout plan
struct WorkoutPlanProposalCard: View {
    let plan: WorkoutPlan
    let message: String
    let onAccept: (() -> Void)?
    let acceptTitle: String
    let onCustomize: (() -> Void)?
    let customizeTitle: String
    let isCompactReview: Bool

    @State private var selectedTemplate: WorkoutPlan.WorkoutTemplate?

    private struct PlanSummaryMetric {
        let value: String
        let label: String
        let footnote: String?
    }

    private var structuredSessionCount: Int {
        plan.templates.filter { $0.sessionType.prefersStructuredEntries }.count
    }

    private var flexibleSessionCount: Int {
        plan.templates.count - structuredSessionCount
    }

    private var summaryMetric: PlanSummaryMetric {
        return PlanSummaryMetric(
            value: "\(plan.templates.count)",
            label: "sessions",
            footnote: flexibleSessionCount > 0 ? "\(flexibleSessionCount) flexible" : nil
        )
    }

    private var averageDurationText: String? {
        let durations = plan.templates.map(\.estimatedDurationMinutes).filter { $0 > 0 }
        guard !durations.isEmpty else { return nil }
        let average = Int((Double(durations.reduce(0, +)) / Double(durations.count)).rounded())
        return "\(average)m avg"
    }

    init(
        plan: WorkoutPlan,
        message: String,
        onAccept: (() -> Void)?,
        acceptTitle: String = "Use This Plan",
        onCustomize: (() -> Void)?,
        customizeTitle: String = "Adjust",
        isCompactReview: Bool = false
    ) {
        self.plan = plan
        self.message = message
        self.onAccept = onAccept
        self.acceptTitle = acceptTitle
        self.onCustomize = onCustomize
        self.customizeTitle = customizeTitle
        self.isCompactReview = isCompactReview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactReview ? 8 : 12) {
            // Trai's message (only show if not empty)
            if !isCompactReview, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Plan summary card
            VStack(alignment: .leading, spacing: isCompactReview ? 10 : 12) {
                // Header
                planHeader

                if !isCompactReview, let intent = plan.planIntent {
                    intentSummary(intent)
                }

                Divider()

                // Templates preview
                templatesPreview

                if onAccept != nil || onCustomize != nil {
                    // Action buttons
                    actionButtons
                }
            }
            .padding(isCompactReview ? 14 : 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            }
        }
        .sheet(item: $selectedTemplate) { template in
            CompactWorkoutDayDetailSheet(template: template)
            .traiSheetBranding()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Plan Header

    private var planHeader: some View {
        HStack {
            Image(systemName: plan.splitType.iconName)
                .font(.title3)
                .foregroundStyle(.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.splitType.displayName)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Session summary
            VStack(alignment: .trailing, spacing: 2) {
                Text(summaryMetric.value)
                    .font(.subheadline)
                    .bold()

                Text(summaryMetric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let averageDurationText {
                    Text(averageDurationText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let footnote = summaryMetric.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Templates Preview

    private var templatesPreview: some View {
        VStack(alignment: .leading, spacing: isCompactReview ? 7 : 8) {
            ForEach(plan.templates) { template in
                if isCompactReview {
                    compactTemplateRow(template)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: template.sessionType.iconName)
                            .font(.caption)
                            .foregroundStyle(template.displayAccentColor)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Text(template.displaySubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(templateMeta(for: template))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func compactTemplateRow(_ template: WorkoutPlan.WorkoutTemplate) -> some View {
        Button {
            HapticManager.lightTap()
            selectedTemplate = template
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.sessionType.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(template.displayAccentColor)
                    .frame(width: 20, height: 20)
                    .background(template.displayAccentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(compactTemplateSubtitle(for: template))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Text(templateMeta(for: template))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .padding(.vertical, 2)
        .buttonStyle(.plain)
    }

    private func templateMeta(for template: WorkoutPlan.WorkoutTemplate) -> String {
        if template.estimatedDurationMinutes > 0 {
            return "\(template.estimatedDurationMinutes)m"
        }
        return template.displayWorkloadSummary
    }

    private func compactTemplateSubtitle(for template: WorkoutPlan.WorkoutTemplate) -> String {
        let supportBlocks = template.displayBlocks
            .filter { block in
                switch block.kind {
                case .cardioFinisher, .cardio, .conditioning, .mobility, .recovery, .skill, .sportPractice:
                    true
                case .warmup, .strength, .cooldown, .custom:
                    false
                }
            }
            .map { block in
                block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? block.kind.displayName
                    : block.title
            }
            .filter { !$0.isEmpty }

        guard !supportBlocks.isEmpty else {
            return template.displaySubtitle
        }

        let baseFocus = template.focusAreas
            .prefix(2)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.localizedCapitalized }
            .joined(separator: " • ")
        let supportText = supportBlocks.prefix(2).joined(separator: " • ")

        if baseFocus.isEmpty {
            return supportText
        }
        return "\(baseFocus) • \(supportText)"
    }

    private var headerSubtitle: String {
        if isCompactReview, let averageDurationText {
            return "\(plan.daysPerWeek) days/week • \(averageDurationText)"
        }
        return "\(plan.daysPerWeek) days/week"
    }

    private func intentSummary(_ intent: WorkoutPlan.PlanIntent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !intent.summary.isEmpty {
                Text(intent.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            FlowLayout(spacing: 6) {
                planSignalChip("\(plan.daysPerWeek)d/week", icon: "calendar")
                if let averageDurationText {
                    planSignalChip(averageDurationText, icon: "clock")
                }
                ForEach(compactIntentSignals(from: intent), id: \.self) { signal in
                    planSignalChip(signal, icon: "checkmark")
                }
            }
        }
    }

    private func compactIntentSignals(from intent: WorkoutPlan.PlanIntent) -> [String] {
        let candidates = intent.honoredInputs + intent.supportingFocuses + intent.avoided.map { "No \($0.lowercased())" }
        var seen: Set<String> = []
        return candidates.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        .prefix(3)
        .map { $0 }
    }

    private func planSignalChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: isCompactReview ? 8 : 12) {
            // Accept button
            if let accept = onAccept {
                Button(action: accept) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(acceptTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiPrimary(color: .accentColor, size: .compact, fullWidth: true, height: isCompactReview ? 38 : nil))
            }

            // Customize button (optional)
            if let customize = onCustomize {
                Button(action: customize) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                        Text(customizeTitle)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.traiTertiary())
            }
        }
    }
}

// MARK: - Plan Accepted Badge

/// Shows a confirmation badge when plan is accepted
struct WorkoutPlanAcceptedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)

            Text("Plan saved!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Plan Updated Badge

/// Shows when a plan was updated after refinement
struct WorkoutPlanUpdatedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundStyle(.accent)

            Text("Plan updated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(.capsule)
    }
}

private struct CompactWorkoutDayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutPlan.WorkoutTemplate

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    blocksCard
                }
                .padding()
            }
            .navigationTitle("Workout Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .tint(.accentColor)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.sessionType.iconName)
                    .font(.headline)
                    .foregroundStyle(template.displayAccentColor)
                    .frame(width: 34, height: 34)
                    .background(template.displayAccentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(template.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if template.estimatedDurationMinutes > 0 {
                    Text("\(template.estimatedDurationMinutes)m")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if template.displayWorkloadSummary != template.sessionType.displayName {
                Text(template.displayWorkloadSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(template.displayAccentColor)
            }

            if let notes = template.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var blocksCard: some View {
        let blocks = template.displayBlocks
        return VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                blockRow(block, tint: template.displayAccentColor)
                if index < blocks.count - 1 {
                    Divider()
                        .padding(.leading, 24)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func blockRow(_ block: WorkoutPlan.TrainingBlock, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: block.kind.iconName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.shortSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !block.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(block.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            WorkoutPlanProposalCard(
                plan: WorkoutPlan(
                    splitType: .pushPullLegs,
                    daysPerWeek: 4,
                    templates: [
                        WorkoutPlan.WorkoutTemplate(
                            name: "Push Day",
                            targetMuscleGroups: ["chest", "shoulders", "triceps"],
                            exercises: [],
                            estimatedDurationMinutes: 45,
                            order: 0
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Pull Day",
                            targetMuscleGroups: ["back", "biceps"],
                            exercises: [],
                            estimatedDurationMinutes: 45,
                            order: 1
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Legs Day",
                            targetMuscleGroups: ["quads", "hamstrings", "calves"],
                            exercises: [],
                            estimatedDurationMinutes: 50,
                            order: 2
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Cardio",
                            targetMuscleGroups: ["cardio"],
                            exercises: [],
                            estimatedDurationMinutes: 30,
                            order: 3
                        )
                    ],
                    rationale: "A classic Push/Pull/Legs split is perfect for your schedule and goals. This gives each muscle group adequate rest while maintaining workout frequency.",
                    guidelines: ["Rest 2-3 minutes between heavy sets"],
                    progressionStrategy: .defaultStrategy,
                    warnings: nil
                ),
                message: "Here's what I put together for you!",
                onAccept: {},
                onCustomize: {}
            )

            WorkoutPlanProposalCard(
                plan: WorkoutPlan(
                    splitType: .custom,
                    daysPerWeek: 4,
                    templates: [
                        WorkoutPlan.WorkoutTemplate(
                            name: "Bouldering Session",
                            sessionType: .climbing,
                            focusAreas: ["Technique", "Endurance"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 75,
                            order: 0
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Upper Strength",
                            sessionType: .strength,
                            focusAreas: ["Upper", "Push"],
                            targetMuscleGroups: ["chest", "shoulders", "triceps"],
                            exercises: [],
                            estimatedDurationMinutes: 55,
                            order: 1
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Mobility Flow",
                            sessionType: .mobility,
                            focusAreas: ["Hips", "Shoulders"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 25,
                            order: 2
                        ),
                        WorkoutPlan.WorkoutTemplate(
                            name: "Trail Run",
                            sessionType: .cardio,
                            focusAreas: ["Zone 2"],
                            targetMuscleGroups: [],
                            exercises: [],
                            estimatedDurationMinutes: 40,
                            order: 3
                        )
                    ],
                    rationale: "A mixed plan that keeps climbing skill work, dedicated strength, and aerobic training all in the same week.",
                    guidelines: [],
                    progressionStrategy: .defaultStrategy,
                    warnings: nil
                ),
                message: "This one mixes structured and flexible sessions cleanly.",
                onAccept: {},
                onCustomize: {}
            )

            WorkoutPlanAcceptedBadge()

            WorkoutPlanUpdatedBadge()
        }
        .padding()
    }
}
