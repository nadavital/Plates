//
//  WorkoutPlanHistoryView.swift
//  Trai
//
//  View for browsing past workout plan versions.
//

import SwiftUI
import SwiftData

struct WorkoutPlanHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var planVersions: [WorkoutPlanVersion] = []
    @State private var selectedVersion: WorkoutPlanVersion?

    var body: some View {
        List {
            if planVersions.isEmpty {
                ContentUnavailableView(
                    "No Workout Plan History",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Your workout plan history will appear here after plan changes.")
                )
            } else {
                ForEach(planVersions) { version in
                    Button {
                        selectedVersion = version
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: WorkoutPlanChangeReason(rawValue: version.reason)?.iconName ?? "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.accent)
                                Text(version.displayReason)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            Text(version.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(version.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedVersion) { version in
            NavigationStack {
                WorkoutPlanVersionDetailView(version: version)
            }
            .traiSheetBranding()
        }
        .onAppear {
            fetchPlanVersions()
        }
    }

    private func fetchPlanVersions() {
        let descriptor = FetchDescriptor<WorkoutPlanVersion>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        planVersions = (try? modelContext.fetch(descriptor)) ?? []
    }
}

private struct WorkoutPlanVersionDetailView: View {
    let version: WorkoutPlanVersion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Change", value: version.displayReason)
                LabeledContent("Date", value: version.formattedDate)
                LabeledContent("Split", value: version.splitTypeDisplayName)
                LabeledContent("Days per week", value: "\(version.daysPerWeek)")
                LabeledContent("Workout days", value: "\(version.templateCount)")
                if version.averageDurationMinutes > 0 {
                    LabeledContent("Avg duration", value: "\(version.averageDurationMinutes) min")
                }
            }

            if version.userWeightKg != nil || version.userGoal != nil {
                Section("Context") {
                    if let weight = version.userWeightKg {
                        LabeledContent("Weight at time", value: String(format: "%.1f kg", weight))
                    }
                    if let goal = version.userGoal {
                        LabeledContent("Goal", value: goal.capitalized)
                    }
                }
            }

            if let plan = version.plan {
                if !plan.templates.isEmpty {
                    Section("Workout Days") {
                        ForEach(plan.templates.sorted(by: { $0.order < $1.order })) { template in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(template.muscleGroupsDisplay)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Progression") {
                    LabeledContent("Type", value: plan.progressionStrategy.type.displayName)
                    if let repsTrigger = plan.progressionStrategy.repsTrigger {
                        LabeledContent("Rep target", value: "\(repsTrigger)")
                    }
                    LabeledContent(
                        "Weight increment",
                        value: String(format: "%.1f kg", plan.progressionStrategy.weightIncrementKg)
                    )
                    Text(plan.progressionStrategy.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !plan.guidelines.isEmpty {
                    Section("Guidelines") {
                        ForEach(plan.guidelines.indices, id: \.self) { index in
                            Text(plan.guidelines[index])
                                .font(.subheadline)
                        }
                    }
                }

                if let warnings = plan.warnings, !warnings.isEmpty {
                    Section("Important Notes") {
                        ForEach(warnings.indices, id: \.self) { index in
                            Text(warnings[index])
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(version.displayReason)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutPlanHistoryView()
    }
    .modelContainer(for: WorkoutPlanVersion.self, inMemory: true)
}
