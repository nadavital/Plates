//
//  WorkoutDetailSheet.swift
//  Trai
//
//  Detailed view of a completed workout session
//

import SwiftUI
import SwiftData

struct WorkoutDetailSheet: View {
    let workout: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTabSelection) private var appTabSelection
    @Environment(\.modelContext) private var modelContext
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @AppStorage(SharedStorageKeys.Chat.pendingPrompt) private var pendingChatPrompt: String = ""
    @AppStorage(SharedStorageKeys.Chat.pendingLaunchLabel) private var pendingChatLaunchLabel: String = ""
    @Query(sort: \ExerciseHistory.performedAt, order: .reverse) private var allExerciseHistory: [ExerciseHistory]
    @Query private var profiles: [UserProfile]
    @State private var isEditingNotes = false
    @State private var noteDraft = ""

    private struct WorkoutStatItem: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        let icon: String
        let color: Color
    }

    private struct DetailItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private var usesMetricExerciseWeight: Bool {
        profiles.first?.usesMetricExerciseWeight ?? true
    }

    private var weightUnit: String {
        usesMetricExerciseWeight ? "kg" : "lbs"
    }

    private var volumePRMode: UserProfile.VolumePRMode {
        profiles.first?.volumePRModeValue ?? .perSet
    }

    private var canAccessTraiChat: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private func displayWeight(_ kg: Double) -> Int {
        let unit = WeightUnit(usesMetric: usesMetricExerciseWeight)
        return WeightUtility.displayInt(kg, displayUnit: unit)
    }

    private func displayVolume(_ volumeKg: Double) -> Int {
        let display = usesMetricExerciseWeight ? volumeKg : (volumeKg * WeightUtility.kgToLbs)
        return Int(display.rounded())
    }

    private func formatVolumePRValue(_ volumeKg: Double) -> String {
        let base = "\(displayVolume(volumeKg)) \(weightUnit)"
        let suffix = volumePRMode.unitSuffix
        if suffix.isEmpty {
            return base
        }
        return "\(base)\(suffix)"
    }

    private var workoutCategoryTitle: String {
        workout.displayTypeName
    }

    private var statsItems: [WorkoutStatItem] {
        var items: [WorkoutStatItem] = []

        if workout.sets > 0 {
            items.append(WorkoutStatItem(
                value: "\(workout.sets)",
                label: "Sets",
                icon: "square.stack.3d.up.fill",
                color: .blue
            ))
        }

        if workout.reps > 0 {
            items.append(WorkoutStatItem(
                value: "\(workout.reps)",
                label: "Reps",
                icon: "repeat",
                color: .green
            ))
        }

        if let weight = workout.weightKg {
            items.append(WorkoutStatItem(
                value: "\(displayWeight(weight))",
                label: weightUnit,
                icon: "scalemass.fill",
                color: .orange
            ))
        }

        if let duration = workout.durationMinutes {
            items.append(WorkoutStatItem(
                value: formatDuration(duration),
                label: "Duration",
                icon: "clock.fill",
                color: .blue
            ))
        }

        if let distance = workout.distanceMeters {
            items.append(WorkoutStatItem(
                value: formatDistance(distance),
                label: "Distance",
                icon: "figure.walk",
                color: .green
            ))
        }

        if let heartRate = workout.averageHeartRate {
            items.append(WorkoutStatItem(
                value: "\(heartRate)",
                label: "Avg BPM",
                icon: "heart.fill",
                color: .pink
            ))
        }

        if let calories = workout.caloriesBurned {
            items.append(WorkoutStatItem(
                value: "\(calories)",
                label: "kcal",
                icon: "flame.fill",
                color: .red
            ))
        }

        return items
    }

    private var detailItems: [DetailItem] {
        var items: [DetailItem] = [
            DetailItem(label: "Type", value: workout.displayTypeName)
        ]

        if workout.isStrengthTraining, let volume = workout.totalVolume {
            items.append(DetailItem(label: "Strength Volume", value: "\(displayVolume(volume)) \(weightUnit)"))
        }

        if workout.sourceIsHealthKit {
            items.append(DetailItem(label: "Source", value: "Apple Health"))
        }

        items.append(
            DetailItem(
                label: "Logged",
                value: workout.loggedAt.formatted(date: .abbreviated, time: .shortened)
            )
        )

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    traiReviewSection

                    // Stats summary
                    if !statsItems.isEmpty {
                        statsSection
                    }

                    // PR highlights (if any)
                    if !prHighlights.isEmpty {
                        prSection
                    }

                    // Workout details
                    detailsSection

                    notesSection

                    // HealthKit info
                    if workout.sourceIsHealthKit {
                        healthKitSection
                    }
                }
                .padding()
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if noteDraft.isEmpty {
                    noteDraft = workout.notes ?? ""
                }
            }
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

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: workout.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            // Name
            Text(workout.displayName)
                .font(.title2)
                .bold()

            Text(workoutCategoryTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Date and time
            Text(workout.loggedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .traiCard()
    }

    private var traiReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(.title3)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review This Session with Trai")
                        .font(.headline)

                    Text("Open Trai with this workout queued up for coaching and next-step feedback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                reviewSessionWithTrai()
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text(canAccessTraiChat ? "Ask Trai About This Session" : "Unlock Trai Coaching")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiSecondary(color: .accentColor, fullWidth: true, fillOpacity: 0.14))
        }
        .traiCard()
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ForEach(statsItems) { item in
                WorkoutStatCard(
                    value: item.value,
                    label: item.label,
                    icon: item.icon,
                    color: item.color
                )
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Details")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(detailItems.enumerated()), id: \.element.id) { index, item in
                    DetailRow(label: item.label, value: item.value)

                    if index < detailItems.count - 1 {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .traiCard()
        }
    }

    // MARK: - PR Section

    private struct PRHighlight: Identifiable {
        let id = UUID()
        let kind: PRMetricKind
        let label: String
        let value: String
    }

    private var prHighlights: [PRHighlight] {
        guard workout.isStrengthTraining else { return [] }

        let exerciseName = workout.displayName
        let previousEntries = allExerciseHistory.filter {
            $0.exerciseName == exerciseName && $0.performedAt < workout.loggedAt
        }
        guard !previousEntries.isEmpty else { return [] }

        var highlights: [PRHighlight] = []

        if let weight = workout.weightKg,
           weight > 0,
           weight > (previousEntries.map(\.bestSetWeightKg).max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .weight,
                label: PRMetricKind.weight.label,
                value: "\(displayWeight(weight)) \(weightUnit)",
            ))
        }

        if workout.reps > 0,
           workout.reps > (previousEntries.map(\.bestSetReps).max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .reps,
                label: PRMetricKind.reps.label,
                value: "\(workout.reps) reps",
            ))
        }

        if let volume = workout.volumeValue(for: volumePRMode),
           volume > 0,
           volume > (previousEntries.map { $0.volumeValue(for: volumePRMode) }.max() ?? 0) {
            highlights.append(PRHighlight(
                kind: .volume,
                label: PRMetricKind.volume.label(for: volumePRMode),
                value: formatVolumePRValue(volume),
            ))
        }

        return highlights
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Personal Records")
                    .font(.headline)
            }

            VStack(spacing: 8) {
                ForEach(prHighlights) { pr in
                    HStack(spacing: 10) {
                        Image(systemName: pr.kind.iconName)
                            .foregroundStyle(pr.kind.color)
                        Text(pr.label)
                            .fontWeight(.medium)
                        Spacer()
                        Text(pr.value)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 10))
                }
            }
            .traiCard()
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trai Notes")
                    .font(.headline)

                Spacer()

                if isEditingNotes {
                    Button("Save") {
                        saveNotes()
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.accentColor)
                } else {
                    Button((workout.notes ?? "").isEmpty ? "Add Note" : "Edit") {
                        noteDraft = workout.notes ?? ""
                        isEditingNotes = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if isEditingNotes {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $noteDraft)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    HStack {
                        Text("Add context like route grade, intervals, energy, technique notes, or what felt different.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Cancel") {
                            noteDraft = workout.notes ?? ""
                            isEditingNotes = false
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            } else if let notes = workout.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.sourceIsHealthKit ? "Imported workout, no Trai notes yet." : "No session notes yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("You can add a quick note afterward so Trai can use it as progression context later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - HealthKit Section

    private var healthKitSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text("Imported from Apple Health")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(totalMinutes)m"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private func saveNotes() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.notes = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        isEditingNotes = false
        HapticManager.selectionChanged()
    }

    private func reviewSessionWithTrai() {
        guard canAccessTraiChat else {
            proUpsellCoordinator?.present(source: .chat)
            HapticManager.lightTap()
            return
        }

        pendingChatPrompt = workout.traiReviewPrompt
        pendingChatLaunchLabel = "Reviewing your latest session..."
        BehaviorTracker(modelContext: modelContext).recordDeferred(
            actionKey: "engagement.review_workout_session_with_trai",
            domain: .engagement,
            surface: .workouts,
            outcome: .opened,
            relatedEntityId: workout.id,
            metadata: [
                "source": workout.sourceIsHealthKit ? "imported_session_detail" : "session_detail",
                "workout_name": workout.displayName
            ]
        )
        dismiss()
        DispatchQueue.main.async {
            appTabSelection.wrappedValue = .trai
        }
        HapticManager.selectionChanged()
    }
}

// MARK: - Workout Stat Card

struct WorkoutStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .traiCard()
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview("WorkoutSession Detail") {
    WorkoutDetailSheet(workout: {
        let workout = WorkoutSession()
        workout.exerciseName = "Evening Climb"
        workout.healthKitWorkoutType = "climbing"
        workout.durationMinutes = 75
        workout.caloriesBurned = 480
        workout.averageHeartRate = 134
        workout.notes = "Focused on technique drills and easier endurance laps."
        return workout
    }())
}
