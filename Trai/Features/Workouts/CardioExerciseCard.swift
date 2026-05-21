//
//  CardioExerciseCard.swift
//  Trai
//
//  Category-aware non-strength exercise card for live workout tracking.
//

import SwiftUI

struct CardioExerciseCard: View {
    let entry: LiveWorkoutEntry
    let usesMetricWeight: Bool
    let onUpdateDuration: (Int) -> Void
    let onUpdateDistance: (Double) -> Void
    var onUpdateCalories: ((Double?) -> Void)?
    var onUpdateSetCount: ((Int?) -> Void)?
    var onUpdateReps: ((Int?) -> Void)?
    var onUpdateWeightKg: ((Double?) -> Void)?
    var onUpdateNotes: ((String) -> Void)?
    let onComplete: () -> Void
    var onDeleteExercise: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false
    @State private var durationMinutes = ""
    @State private var durationSeconds = ""
    @State private var distanceKm = ""
    @State private var calories = ""
    @State private var sets = ""
    @State private var reps = ""
    @State private var weight = ""
    @State private var notes = ""

    private var fields: [Exercise.TrackingField] {
        entry.trackingFields
    }

    private var weightUnit: WeightUnit {
        WeightUnit(usesMetric: usesMetricWeight)
    }

    private var weightUnitLabel: String {
        usesMetricWeight ? "kg" : "lbs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isExpanded {
                VStack(spacing: 12) {
                    if fields.contains(.sets) {
                        setsRow
                    }
                    if fields.contains(.duration) {
                        durationRow
                    }
                    if fields.contains(.distance) {
                        distanceRow
                    }
                    if fields.contains(.reps) {
                        repsRow
                    }
                    if fields.contains(.weight) {
                        weightRow
                    }
                    if fields.contains(.calories) {
                        caloriesRow
                    }
                    if fields.contains(.notes) {
                        notesRow
                    }

                    Button(action: onComplete) {
                        HStack {
                            Image(systemName: entry.completedAt != nil ? "checkmark.circle.fill" : "circle")
                            Text(entry.completedAt != nil ? "Completed" : "Mark Complete")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        .traiTertiary(
                            color: entry.completedAt != nil ? .green : .accentColor,
                            fullWidth: true
                        )
                    )
                }
            }
        }
        .traiCard()
        .onAppear(perform: syncFieldsFromEntry)
        .confirmationDialog(
            "Remove \(entry.exerciseName)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                onDeleteExercise?()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: entry.activityIconName)
                        .font(.subheadline)
                        .foregroundStyle(.accent)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.exerciseName)
                            .font(.headline)

                        if !entry.targetTags.isEmpty {
                            Text(entry.targetTags.prefix(3).joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(Exercise.Category(rawValue: entry.exerciseType)?.displayName ?? "Activity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if onDeleteExercise != nil {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
    }

    private var durationRow: some View {
        trackingRow(icon: "clock.fill", title: "Duration") {
            HStack(spacing: 4) {
                compactNumberField("00", text: $durationMinutes, width: 40)
                    .onChange(of: durationMinutes) { _, _ in updateDuration() }
                Text(":").foregroundStyle(.secondary)
                compactNumberField("00", text: $durationSeconds, width: 40)
                    .onChange(of: durationSeconds) { _, _ in updateDuration() }
            }
        }
    }

    private var distanceRow: some View {
        trackingRow(icon: "map.fill", title: "Distance") {
            HStack(spacing: 4) {
                compactNumberField("0.00", text: $distanceKm, width: 64, keyboard: .decimalPad)
                    .onChange(of: distanceKm) { _, newValue in
                        if let km = Double(newValue) {
                            onUpdateDistance(km * 1000)
                        }
                    }
                Text("km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repsRow: some View {
        trackingRow(icon: "repeat", title: "Reps / Rounds") {
            compactNumberField("0", text: $reps, width: 58)
                .onChange(of: reps) { _, newValue in
                    onUpdateReps?(Int(newValue))
                }
        }
    }

    private var setsRow: some View {
        trackingRow(icon: "number", title: "Sets / Sections") {
            compactNumberField("0", text: $sets, width: 58)
                .onChange(of: sets) { _, newValue in
                    onUpdateSetCount?(Int(newValue))
                }
        }
    }

    private var weightRow: some View {
        trackingRow(icon: "scalemass.fill", title: "Weight") {
            HStack(spacing: 4) {
                compactNumberField("0", text: $weight, width: 64, keyboard: .decimalPad)
                    .onChange(of: weight) { _, newValue in
                        guard let value = Double(newValue) else {
                            onUpdateWeightKg?(nil)
                            return
                        }
                        let kg = usesMetricWeight ? value : value / WeightUtility.kgToLbs
                        onUpdateWeightKg?(kg)
                    }
                Text(weightUnitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var caloriesRow: some View {
        trackingRow(icon: "flame.fill", title: "Calories") {
            compactNumberField("0", text: $calories, width: 58)
                .onChange(of: calories) { _, newValue in
                    onUpdateCalories?(Double(newValue))
                }
        }
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notes", systemImage: "note.text")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Add context", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: notes) { _, value in
                    onUpdateNotes?(value)
                }
        }
    }

    private func trackingRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)

            Spacer()

            content()
        }
    }

    private func compactNumberField(
        _ placeholder: String,
        text: Binding<String>,
        width: CGFloat,
        keyboard: UIKeyboardType = .numberPad
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func updateDuration() {
        let mins = Int(durationMinutes) ?? 0
        let secs = Int(durationSeconds) ?? 0
        onUpdateDuration(mins * 60 + secs)
    }

    private func syncFieldsFromEntry() {
        if let seconds = entry.durationSeconds {
            durationMinutes = "\(seconds / 60)"
            durationSeconds = String(format: "%02d", seconds % 60)
        }
        if let meters = entry.distanceMeters {
            distanceKm = String(format: "%.2f", meters / 1000)
        }
        if let burned = entry.caloriesBurned, burned > 0 {
            calories = String(format: "%.0f", burned)
        }
        if let firstSet = entry.sets.first {
            if !entry.sets.isEmpty {
                sets = "\(entry.sets.count)"
            }
            if firstSet.reps > 0 {
                reps = "\(firstSet.reps)"
            }
            let displayWeight = firstSet.displayWeight(usesMetric: usesMetricWeight)
            if displayWeight > 0 {
                weight = WeightUtility.format(firstSet.weightKg, displayUnit: weightUnit, showUnit: false)
            }
        }
        notes = entry.notes
    }
}
