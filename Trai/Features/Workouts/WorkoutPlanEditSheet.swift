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
    @State private var editorSessionType: WorkoutMode = .strength
    @State private var editorFocusAreasText = ""
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
                sessionType: $editorSessionType,
                focusAreasText: $editorFocusAreasText,
                selectedMuscles: $editorSelectedMuscles,
                onCancel: { showingDayEditor = false },
                onConfirm: {
                    if let templateID = editingTemplateID {
                        updateWorkoutDay(
                            templateID: templateID,
                            name: editorDayName,
                            sessionType: editorSessionType,
                            focusAreas: editorFocusAreas,
                            muscles: editorSelectedMuscles
                        )
                    } else {
                        addWorkoutDay(
                            name: editorDayName,
                            sessionType: editorSessionType,
                            focusAreas: editorFocusAreas,
                            muscles: editorSelectedMuscles
                        )
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

            if editedPlan.progressionStrategy.weightIncrementKg > 0 {
                LabeledContent("Weight increment", value: weightIncrementDisplay)
            }

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
        editorSessionType = orderedTemplates.last?.sessionType ?? .strength
        editorFocusAreasText = ""
        editorSelectedMuscles = [.fullBody]
        showingDayEditor = true
    }

    private func presentEditDaySheet(for template: WorkoutPlan.WorkoutTemplate) {
        editingTemplateID = template.id
        editorDayName = template.name
        editorSessionType = template.sessionType
        editorFocusAreasText = template.focusAreas.joined(separator: ", ")
        let selected = Set(template.targetMuscleGroups.compactMap(normalizeMuscleGroup))
        editorSelectedMuscles = selected.isEmpty ? [.fullBody] : selected
        showingDayEditor = true
    }

    private var editorFocusAreas: [String] {
        sanitizeFocusAreas(editorFocusAreasText.components(separatedBy: ","))
    }

    private func addWorkoutDay(
        name: String,
        sessionType: WorkoutMode,
        focusAreas: [String],
        muscles: Set<LiveWorkout.MuscleGroup>
    ) {
        let targetGroups = targetGroupsForSessionType(sessionType, selectedMuscles: muscles)
        let resolvedFocusAreas = sanitizeFocusAreas(focusAreas.isEmpty ? targetGroups : focusAreas)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty
            ? defaultDayName(
                for: sessionType,
                focusAreas: resolvedFocusAreas.isEmpty ? targetGroups : resolvedFocusAreas,
                dayIndex: orderedTemplates.count + 1
            )
            : trimmedName

        let newTemplate = WorkoutPlan.WorkoutTemplate(
            name: finalName,
            sessionType: sessionType,
            focusAreas: resolvedFocusAreas,
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

    private func updateWorkoutDay(
        templateID: UUID,
        name: String,
        sessionType: WorkoutMode,
        focusAreas: [String],
        muscles: Set<LiveWorkout.MuscleGroup>
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = orderedTemplates.map { template in
            guard template.id == templateID else { return template }
            let targetGroups = targetGroupsForSessionType(
                sessionType,
                selectedMuscles: muscles
            )
            let resolvedFocusAreas = sanitizeFocusAreas(focusAreas.isEmpty ? targetGroups : focusAreas)
            return copyTemplate(
                template,
                name: trimmedName.isEmpty
                    ? defaultDayName(
                        for: sessionType,
                        focusAreas: resolvedFocusAreas.isEmpty ? targetGroups : resolvedFocusAreas,
                        dayIndex: template.order + 1
                    )
                    : trimmedName,
                sessionType: sessionType,
                focusAreas: resolvedFocusAreas,
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
            let targetGroups = template.sessionType.supportsMuscleTargets
                ? sanitizeTargetGroups(template.targetMuscleGroups)
                : []
            let focusAreas = sanitizeFocusAreas(template.focusAreas.isEmpty ? targetGroups : template.focusAreas)
            return copyTemplate(
                template,
                sessionType: template.sessionType,
                focusAreas: focusAreas,
                targetMuscleGroups: targetGroups,
                exercises: [],
                order: index
            )
        }
    }

    private func sanitizeTargetGroups(_ groups: [String]) -> [String] {
        var seen: Set<String> = []
        let normalized: [String] = groups.compactMap { raw in
            if let muscle = normalizeMuscleGroup(raw) {
                if seen.contains(muscle.rawValue) {
                    return nil
                }
                seen.insert(muscle.rawValue)
                return muscle.rawValue
            }

            guard let customGroup = normalizeCustomTargetGroup(raw) else { return nil }
            if seen.contains(customGroup) {
                return nil
            }
            seen.insert(customGroup)
            return customGroup
        }

        if normalized.isEmpty {
            return [LiveWorkout.MuscleGroup.fullBody.rawValue]
        }

        if normalized.count > 1 {
            return normalized.filter { $0 != LiveWorkout.MuscleGroup.fullBody.rawValue }
        }

        return normalized
    }

    private func sanitizeFocusAreas(_ focusAreas: [String]) -> [String] {
        var seen: Set<String> = []
        return focusAreas.compactMap { raw in
            guard let normalized = normalizeCustomTargetGroup(raw) else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
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

    private func normalizeCustomTargetGroup(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: #"(?<=[a-z])(?=[A-Z])"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()

        return normalized.isEmpty ? nil : normalized
    }

    private func targetGroupsForSessionType(
        _ sessionType: WorkoutMode,
        selectedMuscles: Set<LiveWorkout.MuscleGroup>
    ) -> [String] {
        guard sessionType.supportsMuscleTargets else { return [] }
        let selected = selectedMuscles.isEmpty ? Set([LiveWorkout.MuscleGroup.fullBody]) : selectedMuscles
        return sanitizeTargetGroups(orderedTargetGroups(from: selected))
    }

    private func defaultDayName(
        for sessionType: WorkoutMode,
        focusAreas: [String],
        dayIndex: Int
    ) -> String {
        if let primaryFocus = focusAreas.first {
            let formatted = formatFocusAreaName(primaryFocus)
            switch sessionType {
            case .strength, .mixed:
                if formatted.lowercased().contains("day") {
                    return formatted
                }
                return "\(formatted) Day"
            case .cardio, .hiit, .climbing, .yoga, .pilates, .flexibility, .mobility, .recovery, .custom:
                return "\(formatted) \(sessionType == .custom ? "Session" : sessionType.displayName)"
            }
        }

        switch sessionType {
        case .strength:
            return dayIndex == 1 ? "Strength Day" : "Strength Day \(dayIndex)"
        case .mixed:
            return dayIndex == 1 ? "Mixed Training" : "Mixed Training \(dayIndex)"
        case .custom:
            return dayIndex == 1 ? "Custom Session" : "Custom Session \(dayIndex)"
        default:
            return dayIndex == 1 ? sessionType.displayName : "\(sessionType.displayName) \(dayIndex)"
        }
    }

    private func formatFocusAreaName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "hiit":
            return "HIIT"
        case "fullbody":
            return "Full Body"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .localizedCapitalized
        }
    }

    private func copyTemplate(
        _ template: WorkoutPlan.WorkoutTemplate,
        name: String? = nil,
        sessionType: WorkoutMode? = nil,
        focusAreas: [String]? = nil,
        targetMuscleGroups: [String]? = nil,
        exercises: [WorkoutPlan.ExerciseTemplate]? = nil,
        estimatedDurationMinutes: Int? = nil,
        order: Int? = nil
    ) -> WorkoutPlan.WorkoutTemplate {
        WorkoutPlan.WorkoutTemplate(
            id: template.id,
            name: name ?? template.name,
            sessionType: sessionType ?? template.sessionType,
            focusAreas: focusAreas ?? template.focusAreas,
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
            let finalName = trimmedName.isEmpty
                ? defaultDayName(
                    for: template.sessionType,
                    focusAreas: template.focusAreas.isEmpty ? template.targetMuscleGroups : template.focusAreas,
                    dayIndex: index + 1
                )
                : trimmedName
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

                HStack(spacing: 6) {
                    Label(template.sessionType.displayName, systemImage: template.sessionType.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !template.focusAreasDisplay.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(template.focusAreasDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
    private enum Field: Hashable {
        case dayName
        case focusAreas
    }

    let title: String
    let confirmTitle: String
    @Binding var dayName: String
    @Binding var sessionType: WorkoutMode
    @Binding var focusAreasText: String
    @Binding var selectedMuscles: Set<LiveWorkout.MuscleGroup>
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let upperBodyMuscles: [LiveWorkout.MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .forearms]
    private let lowerBodyMuscles: [LiveWorkout.MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]
    private let coreMuscles: [LiveWorkout.MuscleGroup] = [.core]
    @FocusState private var focusedField: Field?

    private var parsedFocusAreas: [String] {
        focusAreasText
            .components(separatedBy: ",")
            .compactMap(normalizeFocusArea)
            .reduce(into: []) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
    }

    private var dayNamePlaceholder: String {
        switch sessionType {
        case .strength:
            return "e.g., Push Day"
        case .cardio:
            return "e.g., Zone 2 Run"
        case .hiit:
            return "e.g., Conditioning Circuit"
        case .climbing:
            return "e.g., Bouldering Session"
        case .yoga:
            return "e.g., Morning Flow"
        case .pilates:
            return "e.g., Core Pilates"
        case .flexibility:
            return "e.g., Full Body Stretch"
        case .mobility:
            return "e.g., Hip Mobility"
        case .mixed:
            return "e.g., Strength + Cardio"
        case .recovery:
            return "e.g., Recovery Walk"
        case .custom:
            return "e.g., Skills Session"
        }
    }

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
                            Text("Choose a session type, then set the focus for that day. Strength days can still target specific muscles.")
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

                            TextField(dayNamePlaceholder, text: $dayName)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .dayName)
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
                        Text("Session Type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(WorkoutMode.allCases) { mode in
                                SessionTypeTile(
                                    mode: mode,
                                    isSelected: sessionType == mode
                                ) {
                                    sessionType = mode
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Focus Areas")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(sessionType.supportsMuscleTargets
                             ? "Add a freeform focus like Push, Pull, Skills, or Performance."
                             : "Describe the style of session, skill, or energy system you want this day to cover.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 8) {
                            ForEach(sessionType.suggestedFocusPresets, id: \.self) { preset in
                                DayPresetChip(
                                    title: preset,
                                    isSelected: parsedFocusAreas.contains(normalizeFocusArea(preset) ?? "")
                                ) {
                                    if sessionType.supportsMuscleTargets {
                                        applyStrengthPreset(named: preset)
                                    } else {
                                        toggleFocusPreset(preset)
                                    }
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)

                            TextField("e.g., Flow, Bouldering, Zone 2, Conditioning", text: $focusAreasText, axis: .vertical)
                                .lineLimit(2...4)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .focusAreas)
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

                    if sessionType.supportsMuscleTargets {
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
                }
                .padding()
                .contentShape(Rectangle())
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onTapGesture {
                focusedField = nil
            }
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
        .onChange(of: sessionType) { _, newValue in
            if newValue.supportsMuscleTargets {
                if selectedMuscles.isEmpty {
                    selectedMuscles = [.fullBody]
                }
            } else {
                selectedMuscles = []
            }
        }
    }

    private func applyPreset(_ muscles: [LiveWorkout.MuscleGroup]) {
        selectedMuscles = Set(muscles)
    }

    private func applyStrengthPreset(named preset: String) {
        let normalizedPreset = preset.lowercased()
        switch normalizedPreset {
        case "push":
            applyPreset(LiveWorkout.MuscleGroup.pushMuscles)
        case "pull":
            applyPreset(LiveWorkout.MuscleGroup.pullMuscles)
        case "legs":
            applyPreset(LiveWorkout.MuscleGroup.legMuscles)
        case "upper":
            applyPreset([.chest, .back, .shoulders, .biceps, .triceps, .forearms])
        case "full body":
            applyPreset([.fullBody])
        default:
            break
        }

        focusAreasText = preset
    }

    private func toggleFocusPreset(_ preset: String) {
        guard let normalizedPreset = normalizeFocusArea(preset) else { return }
        var updated = parsedFocusAreas
        if let existingIndex = updated.firstIndex(of: normalizedPreset) {
            updated.remove(at: existingIndex)
        } else {
            updated.append(normalizedPreset)
        }
        focusAreasText = updated.map(displayFocusArea).joined(separator: ", ")
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

    private func normalizeFocusArea(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func displayFocusArea(_ raw: String) -> String {
        switch raw {
        case "hiit":
            return "HIIT"
        case "full body":
            return "Full Body"
        case "zone 2":
            return "Zone 2"
        default:
            return raw.localizedCapitalized
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
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct SessionTypeTile: View {
    let mode: WorkoutMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.iconName)
                    .font(.subheadline)

                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

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

#Preview {
    WorkoutPlanEditSheet(
        currentPlan: WorkoutPlan(
            splitType: .custom,
            daysPerWeek: 3,
            templates: [
                WorkoutPlan.WorkoutTemplate(
                    name: "Push Day",
                    sessionType: .strength,
                    focusAreas: ["push"],
                    targetMuscleGroups: ["chest", "shoulders", "triceps"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 0
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Pull Day",
                    sessionType: .strength,
                    focusAreas: ["pull"],
                    targetMuscleGroups: ["back", "biceps"],
                    exercises: [],
                    estimatedDurationMinutes: 45,
                    order: 1
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Climbing Technique",
                    sessionType: .climbing,
                    focusAreas: ["bouldering", "technique"],
                    targetMuscleGroups: [],
                    exercises: [],
                    estimatedDurationMinutes: 60,
                    order: 2
                ),
                WorkoutPlan.WorkoutTemplate(
                    name: "Leg Day",
                    sessionType: .strength,
                    focusAreas: ["legs"],
                    targetMuscleGroups: ["quads", "hamstrings", "glutes", "calves"],
                    exercises: [],
                    estimatedDurationMinutes: 50,
                    order: 3
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
