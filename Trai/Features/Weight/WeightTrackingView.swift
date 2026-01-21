//
//  WeightTrackingView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData
import Charts

struct WeightTrackingView: View {
    @Query(sort: \WeightEntry.loggedAt, order: .reverse)
    private var weightEntries: [WeightEntry]

    @Query private var profiles: [UserProfile]

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddWeight = false
    @State private var healthKitService = HealthKitService()
    @State private var selectedTimeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        case year = "Year"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .year: return 365
            }
        }
    }

    private var profile: UserProfile? { profiles.first }

    private var useLbs: Bool {
        !(profile?.usesMetricWeight ?? true)
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    private func displayWeight(_ weightKg: Double) -> Double {
        useLbs ? weightKg * 2.20462 : weightKg
    }

    private var filteredEntries: [WeightEntry] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedTimeRange.days, to: Date()) ?? Date()
        return weightEntries.filter { $0.loggedAt >= cutoffDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current weight card
                    if let latest = weightEntries.first {
                        CurrentWeightCard(
                            entry: latest,
                            targetWeight: profile?.targetWeightKg,
                            useLbs: useLbs
                        )
                    }

                    // Time range picker
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Weight chart
                    if filteredEntries.count > 1 {
                        WeightChartView(
                            entries: filteredEntries.reversed(),
                            targetWeight: profile?.targetWeightKg,
                            useLbs: useLbs
                        )
                    }

                    // Weight history list
                    WeightHistoryList(entries: Array(weightEntries.prefix(10)), useLbs: useLbs)
                }
                .padding()
            }
            .navigationTitle("Weight")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") {
                        showingAddWeight = true
                    }
                }
            }
            .sheet(isPresented: $showingAddWeight) {
                AddWeightView()
            }
            .refreshable {
                await syncHealthKit()
            }
        }
    }

    private func syncHealthKit() async {
        do {
            try await healthKitService.requestAuthorization()

            let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            let healthKitEntries = try await healthKitService.fetchWeightEntries(from: threeMonthsAgo, to: Date())

            let existingIDs = Set(weightEntries.compactMap { $0.healthKitSampleID })
            let newEntries = healthKitEntries.filter { !existingIDs.contains($0.healthKitSampleID ?? "") }

            for entry in newEntries {
                modelContext.insert(entry)
            }
        } catch {
            // Handle error silently
        }
    }
}

// MARK: - Current Weight Card

struct CurrentWeightCard: View {
    let entry: WeightEntry
    let targetWeight: Double?
    var useLbs: Bool = false

    private var displayWeight: Double {
        useLbs ? entry.weightKg * 2.20462 : entry.weightKg
    }

    private var displayTarget: Double? {
        guard let target = targetWeight else { return nil }
        return useLbs ? target * 2.20462 : target
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Current Weight")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(displayWeight, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 48, weight: .bold))

                Text(weightUnit)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if let target = displayTarget {
                let difference = displayWeight - target
                HStack {
                    Image(systemName: difference > 0 ? "arrow.down" : "arrow.up")
                    Text("\(abs(difference), format: .number.precision(.fractionLength(1))) \(weightUnit) to goal")
                }
                .font(.subheadline)
                .foregroundStyle(difference > 0 ? .orange : .green)
            }

            Text("Last updated: \(entry.loggedAt, format: .dateTime.month().day().hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Weight Chart View

struct WeightChartView: View {
    let entries: [WeightEntry]
    let targetWeight: Double?
    var useLbs: Bool = false

    private func displayWeight(_ weightKg: Double) -> Double {
        useLbs ? weightKg * 2.20462 : weightKg
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend")
                .font(.headline)

            Chart {
                ForEach(entries) { entry in
                    LineMark(
                        x: .value("Date", entry.loggedAt),
                        y: .value("Weight", displayWeight(entry.weightKg))
                    )
                    .foregroundStyle(.tint)

                    PointMark(
                        x: .value("Date", entry.loggedAt),
                        y: .value("Weight", displayWeight(entry.weightKg))
                    )
                    .foregroundStyle(.tint)
                }

                if let target = targetWeight {
                    RuleMark(y: .value("Goal", displayWeight(target)))
                        .foregroundStyle(.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Weight History List

struct WeightHistoryList: View {
    let entries: [WeightEntry]
    var useLbs: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Entries")
                .font(.headline)

            if entries.isEmpty {
                Text("No weight entries yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(entries) { entry in
                    WeightEntryRow(entry: entry, useLbs: useLbs)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct WeightEntryRow: View {
    let entry: WeightEntry
    var useLbs: Bool = false

    private var displayWeight: Double {
        useLbs ? entry.weightKg * 2.20462 : entry.weightKg
    }

    private var weightUnit: String {
        useLbs ? "lbs" : "kg"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.loggedAt, format: .dateTime.weekday(.abbreviated).month().day())
                    .font(.body)

                if entry.sourceIsHealthKit {
                    Label("From Apple Health", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Text("\(displayWeight, format: .number.precision(.fractionLength(1))) \(weightUnit)")
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WeightTrackingView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self], inMemory: true)
}
