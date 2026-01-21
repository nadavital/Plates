//
//  PlanHistoryView.swift
//  Trai
//
//  View for browsing past nutrition plan versions.
//

import SwiftUI
import SwiftData

struct PlanHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var planVersions: [NutritionPlanVersion] = []
    @State private var selectedVersion: NutritionPlanVersion?

    var body: some View {
        List {
            if planVersions.isEmpty {
                ContentUnavailableView(
                    "No Plan History",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Your nutrition plan history will appear here after changes are made.")
                )
            } else {
                ForEach(planVersions) { version in
                    Button {
                        selectedVersion = version
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(version.displayReason)
                                .font(.headline)
                                .foregroundStyle(.primary)

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
        .navigationTitle("Plan History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedVersion) { version in
            NavigationStack {
                PlanVersionDetailView(version: version)
            }
        }
        .onAppear {
            fetchPlanVersions()
        }
    }

    private func fetchPlanVersions() {
        let descriptor = FetchDescriptor<NutritionPlanVersion>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        planVersions = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Plan Version Detail

private struct PlanVersionDetailView: View {
    let version: NutritionPlanVersion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Daily Targets") {
                LabeledContent("Calories", value: "\(version.calorieTarget) kcal")
                LabeledContent("Protein", value: "\(version.proteinTarget)g")
                LabeledContent("Carbs", value: "\(version.carbsTarget)g")
                LabeledContent("Fat", value: "\(version.fatTarget)g")
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

            if let plan = version.plan, !plan.rationale.isEmpty {
                Section("Rationale") {
                    Text(plan.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(version.displayReason)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlanHistoryView()
    }
    .modelContainer(for: NutritionPlanVersion.self, inMemory: true)
}
