//
//  LogWeightSheet.swift
//  Trai
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData

struct LogWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var recentEntries: [WeightEntry]

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var showBodyFat = false
    @State private var notes = ""
    @State private var logDate = Date()
    @State private var hasInitialized = false
    @FocusState private var isWeightFocused: Bool

    private var profile: UserProfile? { profiles.first }

    private var usesMetric: Bool {
        profile?.usesMetricWeight ?? true
    }

    private var unitLabel: String {
        usesMetric ? "kg" : "lbs"
    }

    private var lastWeight: Double? {
        guard let entry = recentEntries.first else { return nil }
        return usesMetric ? entry.weightKg : entry.weightLbs
    }

    private var weightValue: Double? {
        Double(weightText.replacing(",", with: "."))
    }

    private var bodyFatValue: Double? {
        Double(bodyFatText.replacing(",", with: "."))
    }

    private var isValidWeight: Bool {
        guard let weight = weightValue else { return false }
        let range: ClosedRange<Double> = usesMetric ? 20.0...300.0 : 44.0...660.0
        return range.contains(weight)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Weight input section
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0.0", text: $weightText)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($isWeightFocused)
                            .frame(maxWidth: .infinity)

                        Text(unitLabel)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } header: {
                    Text("Weight")
                }

                // Date section
                Section {
                    DatePicker(
                        "Date",
                        selection: $logDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                // Body fat section (optional)
                Section {
                    Toggle("Track Body Fat", isOn: $showBodyFat.animation())

                    if showBodyFat {
                        HStack {
                            Text("Body Fat")
                            Spacer()
                            TextField("0.0", text: $bodyFatText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if showBodyFat {
                        Text("Body fat percentage helps track body composition changes")
                    }
                }

                // Notes section
                Section {
                    TextField("Add notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Notes")
                }

                // Recent entries preview
                if !recentEntries.isEmpty {
                    Section {
                        ForEach(recentEntries.prefix(3)) { entry in
                            RecentWeightRow(entry: entry, usesMetric: usesMetric)
                        }
                    } header: {
                        Text("Recent Entries")
                    }
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        saveWeight()
                    }
                    .disabled(!isValidWeight)
                }
            }
            .onAppear {
                initializeWeight()
                isWeightFocused = true
            }
        }
        .traiBackground()
    }

    private func initializeWeight() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Pre-fill with last weight for convenience
        if let last = lastWeight {
            weightText = String(format: "%.1f", last)
        } else if let current = profile?.currentWeightKg {
            let weight = usesMetric ? current : current * 2.20462
            weightText = String(format: "%.1f", weight)
        }
    }

    private func saveWeight() {
        guard let weight = weightValue else { return }
        let weightKg = usesMetric ? weight : weight / 2.20462

        let entry = WeightEntry(
            weightKg: weightKg,
            bodyFatPercentage: showBodyFat ? bodyFatValue : nil,
            leanMassKg: nil,
            loggedAt: logDate
        )

        entry.notes = notes.isEmpty ? nil : notes

        modelContext.insert(entry)
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.logWeight,
            domain: .body,
            surface: .weight,
            outcome: .completed,
            relatedEntityId: entry.id,
            metadata: [
                "unit": unitLabel,
                "source": "manual_sheet"
            ]
        )

        // Update profile's current weight
        if let profile {
            profile.currentWeightKg = weightKg

            // Sync to Apple Health if enabled
            if profile.syncWeightToHealthKit {
                Task {
                    guard let healthKitService else { return }
                    try? await healthKitService.saveWeightAuthorized(weightKg, date: logDate)
                }
            }
        }

        HapticManager.success()
        dismiss()
    }
}

// MARK: - Recent Weight Row

private struct RecentWeightRow: View {
    let entry: WeightEntry
    let usesMetric: Bool

    private var displayWeight: Double {
        usesMetric ? entry.weightKg : entry.weightLbs
    }

    private var unitLabel: String {
        usesMetric ? "kg" : "lbs"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.loggedAt, style: .date)
                    .font(.subheadline)

                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayWeight, format: .number.precision(.fractionLength(1)))
                    .font(.headline)
                Text(unitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LogWeightSheet()
        .modelContainer(for: [UserProfile.self, WeightEntry.self], inMemory: true)
}
