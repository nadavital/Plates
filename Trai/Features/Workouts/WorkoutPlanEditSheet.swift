//
//  WorkoutPlanEditSheet.swift
//  Trai
//
//  Unified workout plan management screen (details + editing)
//

import SwiftUI
import SwiftData

struct WorkoutPlanEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    private var userProfile: UserProfile? { profiles.first }

    let currentPlan: WorkoutPlan

    @State private var showingFullSetup = false
    @State private var showingDayEditor = false
    @State private var editingTemplateID: UUID?
    @State private var editorDayName = ""
    @State private var editorSelectedMuscles: Set<LiveWorkout.MuscleGroup> = [.fullBody]
    @State private var editedPlan: WorkoutPlan
    @State private var hasPendingChanges = false

    init(currentPlan: WorkoutPlan) {
        self.currentPlan = currentPlan
        self._editedPlan = State(initialValue: currentPlan)
    }

    private var orderedTemplates: [WorkoutPlan.WorkoutTemplate] {
        editedPlan.templates.sorted(by: { $0.order < $1.order })
    }

    private var weightIncrementDisplay: String {
        let kg = editedPlan.progressionStrategy.weightIncrementKg
        if userProfile?.usesMetricExerciseWeight ?? true {
            return String(format: "%.1f kg", kg)
        } else {
            return String(format: "%.1f lbs", kg * 2.20462)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                preferencesSection
                workoutDaysSection
                progressionSection
                guidelinesSection
                warningsSection
                quickActionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        savePlan(editedPlan)
                        hasPendingChanges = false
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .tint(.accentColor)
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullSetup) {
            WorkoutPlanChatFlow()
                .traiSheetBranding()
        }
        .sheet(isPresented: $showingDayEditor) {
            WorkoutDayEditorSheet(
                title: editingTemplateID == nil ? "Add Workout Day" : "Edit Workout Day",
                confirmTitle: editingTemplateID == nil ? "Add" : "Save",
                dayName: $editorDayName,
                selectedMuscles: $editorSelectedMuscles,
                onCancel: { showingDayEditor = false },
                onConfirm: {
                    if let templateID = editingTemplateID {
                        updateWorkoutDay(templateID: templateID, name: editorDayName, muscles: editorSelectedMuscles)
                    } else {
                        addWorkoutDay(name: editorDayName, muscles: editorSelectedMuscles)
                    }
                    showingDayEditor = false
                }
            )
            .traiSheetBranding()
        }
    }

    private var summarySection: some View {
        Section {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: editedPlan.splitType.iconName)
                        .foregroundStyle(.accent)
                    Text(editedPlan.splitType.displayName)
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(editedPlan.daysPerWeek)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("days/week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text("\(editedPlan.templates.count)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text("workouts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text("~\(editedPlan.templates.first?.estimatedDurationMinutes ?? 45)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("min avg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                if !editedPlan.rationale.isEmpty {
                    Text(editedPlan.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .listRowInsets(.init(top: 10, leading: 0, bottom: 10, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Stepper(
                value: Binding(
                    get: { editedPlan.daysPerWeek },
                    set: { updateDaysPerWeek($0) }
                ),
                in: max(1, editedPlan.templates.count)...7
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training days per week: \(editedPlan.daysPerWeek)")
                    Text("Workout suggestions are based on your selected muscles and exercise history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(
                value: Binding(
                    get: { averageWorkoutDuration },
                    set: { updateAverageWorkoutDuration($0) }
                ),
                in: 20...120,
                step: 5
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Average workout length: \(averageWorkoutDuration) min")
                    Text("Applies to every workout day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var workoutDaysSection: some View {
        Section("Workout Days") {
            ForEach(orderedTemplates) { template in
                Button {
                    presentEditDaySheet(for: template)
                } label: {
                    WorkoutDayRow(template: template)
                }
                .buttonStyle(.plain)
                .deleteDisabled(orderedTemplates.count <= 1)
            }
            .onDelete(perform: deleteWorkoutDays)

            Button {
                presentAddDaySheet()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.accent)
                    Text("Add Workout Day")
                }
            }
        }
    }

    private var progressionSection: some View {
        Section("Progression Strategy") {
            LabeledContent("Type", value: editedPlan.progressionStrategy.type.displayName)

            if let repsTrigger = editedPlan.progressionStrategy.repsTrigger {
                LabeledContent("Rep target", value: "\(repsTrigger)")
            }

            LabeledContent("Weight increment", value: weightIncrementDisplay)

            Text(editedPlan.progressionStrategy.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var guidelinesSection: some View {
        if !editedPlan.guidelines.isEmpty {
            Section("Guidelines") {
                ForEach(editedPlan.guidelines.indices, id: \.self) { index in
                    Text(editedPlan.guidelines[index])
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if let warnings = editedPlan.warnings, !warnings.isEmpty {
            Section("Important Notes") {
                ForEach(warnings.indices, id: \.self) { index in
                    Text(warnings[index])
                        .font(.subheadline)
                }
            }
        }
    }

    private var quickActionsSection: some View {
        Section {
            Button {
                showingFullSetup = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start Fresh")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func presentAddDaySheet() {
        editingTemplateID = nil
        editorDayName = ""
        editorSelectedMuscles = [.fullBody]
        showingDayEditor = true
    }

    private func presentEditDaySheet(for template: WorkoutPlan.WorkoutTemplate) {
        editingTemplateID = template.id
        editorDayName = template.name
        let selected = Set(template.targetMuscleGroups.compactMap(normalizeMuscleGroup))
        editorSelectedMuscles = selected.isEmpty ? [.fullBody] : selected
        showingDayEditor = true
    }

    private func addWorkoutDay(name: String, muscles: Set<LiveWorkout.MuscleGroup>) {
        let selectedMuscles = muscles.isEmpty ? [.fullBody] : muscles
        let targetGroups = orderedTargetGroups(from: selectedMuscles)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Workout Day \(orderedTemplates.count + 1)" : trimmedName

        let newTemplate = WorkoutPlan.WorkoutTemplate(
            name: finalName,
            targetMuscleGroups: targetGroups,
            exercises: [],
            estimatedDurationMinutes: editedPlan.templates.first?.estimatedDurationMinutes ?? 45,
            order: orderedTemplates.count
        )

        let updated = normalizeTemplates(orderedTemplates + [newTemplate])
        updatePlan(
            splitType: .custom,
            daysPerWeek: max(editedPlan.daysPerWeek, updated.count),
            templates: updated
        )
    }

    private func updateWorkoutDay(templateID: UUID, name: String, muscles: Set<LiveWorkout.MuscleGroup>) {
        let targetGroups = orderedTargetGroups(from: muscles)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = orderedTemplates.map { template in
            guard template.id == templateID else { return template }
            return copyTemplate(
                template,
                name: trimmedName.isEmpty ? template.name : trimmedName,
                targetMuscleGroups: targetGroups
            )
        }

        updatePlan(splitType: .custom, templates: normalizeTemplates(updated))
    }

    private func deleteWorkoutDays(at offsets: IndexSet) {
        guard orderedTemplates.count > 1 else { return }

        let idsToDelete = Set(offsets.map { orderedTemplates[$0].id })
        let remaining = orderedTemplates.filter { !idsToDelete.contains($0.id) }
        guard !remaining.isEmpty else { return }

        let updated = normalizeTemplates(remaining)
        updatePlan(
            splitType: .custom,
            daysPerWeek: max(editedPlan.daysPerWeek, updated.count),
            templates: updated
        )
    }

    private func updatePlan(
        splitType: WorkoutPlan.SplitType? = nil,
        daysPerWeek: Int? = nil,
        templates: [WorkoutPlan.WorkoutTemplate]? = nil
    ) {
        editedPlan = WorkoutPlan(
            splitType: splitType ?? editedPlan.splitType,
            daysPerWeek: daysPerWeek ?? editedPlan.daysPerWeek,
            templates: templates ?? editedPlan.templates,
            rationale: editedPlan.rationale,
            guidelines: editedPlan.guidelines,
            progressionStrategy: editedPlan.progressionStrategy,
            warnings: editedPlan.warnings
        )
        hasPendingChanges = editedPlan != currentPlan
    }

    private func updateDaysPerWeek(_ days: Int) {
        updatePlan(daysPerWeek: max(days, editedPlan.templates.count))
    }

    private var averageWorkoutDuration: Int {
        let templates = editedPlan.templates
        guard !templates.isEmpty else { return 45 }
        return templates.map(\.estimatedDurationMinutes).reduce(0, +) / templates.count
    }

    private func updateAverageWorkoutDuration(_ minutes: Int) {
        let updatedTemplates = orderedTemplates.map { template in
            copyTemplate(template, estimatedDurationMinutes: minutes)
        }
        updatePlan(templates: normalizeTemplates(updatedTemplates))
    }

    private func orderedTargetGroups(from muscles: Set<LiveWorkout.MuscleGroup>) -> [String] {
        let selected = muscles.isEmpty ? Set([LiveWorkout.MuscleGroup.fullBody]) : muscles
        return LiveWorkout.MuscleGroup.allCases
            .filter { selected.contains($0) }
            .map(\.rawValue)
    }

    private func normalizeTemplates(_ templates: [WorkoutPlan.WorkoutTemplate]) -> [WorkoutPlan.WorkoutTemplate] {
        templates.enumerated().map { index, template in
            copyTemplate(
                template,
                targetMuscleGroups: sanitizeTargetGroups(template.targetMuscleGroups),
                exercises: [],
                order: index
            )
        }
    }

    private func sanitizeTargetGroups(_ groups: [String]) -> [String] {
        var seen: Set<String> = []
        let normalized: [String] = groups.compactMap { raw in
            guard let muscle = normalizeMuscleGroup(raw) else { return nil }
            if seen.contains(muscle.rawValue) {
                return nil
            }
            seen.insert(muscle.rawValue)
            return muscle.rawValue
        }

        if normalized.isEmpty {
            return [LiveWorkout.MuscleGroup.fullBody.rawValue]
        }

        if normalized.count > 1 {
            return normalized.filter { $0 != LiveWorkout.MuscleGroup.fullBody.rawValue }
        }

        return normalized
    }

    private func normalizeMuscleGroup(_ raw: String) -> LiveWorkout.MuscleGroup? {
        if let exact = LiveWorkout.MuscleGroup(rawValue: raw) {
            return exact
        }

        let lowered = raw.lowercased()
        if lowered == "fullbody" {
            return .fullBody
        }

        return LiveWorkout.MuscleGroup(rawValue: lowered)
    }

    private func copyTemplate(
        _ template: WorkoutPlan.WorkoutTemplate,
        name: String? = nil,
        targetMuscleGroups: [String]? = nil,
        exercises: [WorkoutPlan.ExerciseTemplate]? = nil,
        estimatedDurationMinutes: Int? = nil,
        order: Int? = nil
    ) -> WorkoutPlan.WorkoutTemplate {
        WorkoutPlan.WorkoutTemplate(
            id: template.id,
            name: name ?? template.name,
            targetMuscleGroups: targetMuscleGroups ?? template.targetMuscleGroups,
            exercises: exercises ?? template.exercises,
            estimatedDurationMinutes: estimatedDurationMinutes ?? template.estimatedDurationMinutes,
            order: order ?? template.order,
            notes: template.notes
        )
    }

    private func normalizedPlanForSave(_ plan: WorkoutPlan) -> WorkoutPlan {
        let templates = normalizeTemplates(plan.templates).enumerated().map { index, template in
            let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? "Workout Day \(index + 1)" : trimmedName
            return copyTemplate(template, name: finalName, exercises: [], order: index)
        }

        return WorkoutPlan(
            splitType: plan.splitType,
            daysPerWeek: max(plan.daysPerWeek, templates.count),
            templates: templates,
            rationale: plan.rationale,
            guidelines: plan.guidelines,
            progressionStrategy: plan.progressionStrategy,
            warnings: plan.warnings
        )
    }

    private func savePlan(_ plan: WorkoutPlan) {
        guard let profile = userProfile else { return }
        let normalizedPlan = normalizedPlanForSave(plan)
        WorkoutPlanHistoryService.archiveCurrentPlanIfExists(
            profile: profile,
            reason: .manualEdit,
            modelContext: modelContext,
            replacingWith: normalizedPlan
        )
        profile.workoutPlan = normalizedPlan
        try? modelContext.save()
    }
}

private struct WorkoutDayRow: View {
    let template: WorkoutPlan.WorkoutTemplate

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(template.muscleGroupsDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct WorkoutDayEditorSheet: View {
    let title: String
    let confirmTitle: String
    @Binding var dayName: String
    @Binding var selectedMuscles: Set<LiveWorkout.MuscleGroup>
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let upperBodyMuscles: [LiveWorkout.MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .forearms]
    private let lowerBodyMuscles: [LiveWorkout.MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]
    private let coreMuscles: [LiveWorkout.MuscleGroup] = [.core]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Customize This Day")
                                .font(.headline)
                            Text("Set a day name and target muscles. Suggestions use your history.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Day Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: "pencil.line")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("e.g., Back + Arms", text: $dayName)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.18), lineWidth: 1)
                        }
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Presets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            DayPresetChip(title: "Push") { applyPreset(LiveWorkout.MuscleGroup.pushMuscles) }
                            DayPresetChip(title: "Pull") { applyPreset(LiveWorkout.MuscleGroup.pullMuscles) }
                            DayPresetChip(title: "Legs") { applyPreset(LiveWorkout.MuscleGroup.legMuscles) }
                            DayPresetChip(title: "Upper") {
                                applyPreset([.chest, .back, .shoulders, .biceps, .triceps, .forearms])
                            }
                            DayPresetChip(title: "Full Body") { applyPreset([.fullBody]) }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Target Muscles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Grouped by region for faster setup.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        muscleTileGroup(title: "Upper Body", muscles: upperBodyMuscles)
                        muscleTileGroup(title: "Lower Body", muscles: lowerBodyMuscles)
                        muscleTileGroup(title: "Core", muscles: coreMuscles)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, systemImage: "checkmark", action: onConfirm)
                        .labelStyle(.iconOnly)
                        .tint(.accentColor)
                }
            }
        }
        .traiSheetBranding()
    }

    private func applyPreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        selectedMuscles = Set(muscles)
    }

    private func toggleMuscle(_ muscle: LiveWorkout.MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }

        if muscle != .fullBody {
            selectedMuscles.remove(.fullBody)
        }

        if selectedMuscles.isEmpty {
            selectedMuscles.insert(.fullBody)
        }
    }

    @ViewBuilder
    private func muscleTileGroup(title: String, muscles: [LiveWorkout.MuscleGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(muscles) { muscle in
                    DayMuscleTile(
                        muscle: muscle,
                        isSelected: selectedMuscles.contains(muscle)
                    ) {
                        toggleMuscle(muscle)
                    }
                }
            }
        }
    }
}

private struct DayMuscleTile: View {
    let muscle: LiveWorkout.MuscleGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: muscle.iconName)
                    .font(.subheadline)
                Text(muscle.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct DayPresetChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WorkoutPlanEditSheet(
        currentPlan: WorkoutPlan(
            splitType: .custom,
            daysPerWeek: 3,
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
                    name: "Leg Day",
                    targetMuscleGroups: ["quads", "hamstrings", "glutes", "calves"],
                    exercises: [],
                    estimatedDurationMinutes: 50,
                    order: 2
                )
            ],
            rationale: "A custom split based on your preferences and recovery.",
            guidelines: [
                "Progress gradually and prioritize form.",
                "Leave at least one day between heavy sessions for the same muscles."
            ],
            progressionStrategy: .defaultStrategy,
            warnings: ["Reduce volume if recovery drops for multiple days."]
        )
    )
    .modelContainer(for: [UserProfile.self], inMemory: true)
}
