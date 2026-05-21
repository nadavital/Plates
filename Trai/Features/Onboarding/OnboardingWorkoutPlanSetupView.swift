//
//  OnboardingWorkoutPlanSetupView.swift
//  Trai
//
//  Card-based workout plan setup for onboarding.
//

import SwiftUI

struct OnboardingWorkoutPlanUserContext: Equatable {
    let name: String
    let age: Int
    let gender: UserProfile.Gender
    let goal: UserProfile.GoalType
    let activityLevel: UserProfile.ActivityLevel
    let nutritionContext: [String]
    let memoryContext: [String]
    let activeWorkoutGoalContext: [String]

    init(
        name: String,
        age: Int,
        gender: UserProfile.Gender,
        goal: UserProfile.GoalType,
        activityLevel: UserProfile.ActivityLevel,
        nutritionContext: [String] = [],
        memoryContext: [String] = [],
        activeWorkoutGoalContext: [String] = []
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.goal = goal
        self.activityLevel = activityLevel
        self.nutritionContext = nutritionContext
        self.memoryContext = memoryContext
        self.activeWorkoutGoalContext = activeWorkoutGoalContext
    }
}

extension OnboardingWorkoutPlanUserContext {
    static func nutritionContext(from profile: UserProfile?) -> [String] {
        guard let profile else { return [] }
        var context: [String] = [
            "Nutrition goal: \(profile.goal.displayName)",
            "Daily targets: \(profile.dailyCalorieGoal) calories, \(profile.dailyProteinGoal)g protein, \(profile.dailyCarbsGoal)g carbs, \(profile.dailyFatGoal)g fat"
        ]

        if let trainingDayCalories = profile.trainingDayCalories {
            context.append("Training day calories: \(trainingDayCalories)")
        }
        if let restDayCalories = profile.restDayCalories {
            context.append("Rest day calories: \(restDayCalories)")
        }
        if !profile.activityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.append("Activity notes: \(profile.activityNotes)")
        }
        if !profile.additionalGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.append("Goal notes from onboarding: \(profile.additionalGoalNotes)")
        }
        if let json = profile.savedPlanJSON,
           let plan = NutritionPlan.fromJSON(json) {
            context.append("Nutrition plan rationale: \(plan.rationale)")
            if let adjustment = plan.weeklyAdjustments?.recommendation, !adjustment.isEmpty {
                context.append("Nutrition weekly adjustment: \(adjustment)")
            }
            if let milestone = plan.progressInsights?.shortTermMilestone, !milestone.isEmpty {
                context.append("Nutrition milestone: \(milestone)")
            }
        }

        return context
    }

    static func activeGoalContext(from goals: [WorkoutGoal]) -> [String] {
        goals
            .filter { $0.status == .active }
            .prefix(5)
            .map { goal in
                var parts = [goal.trimmedTitle]
                if let mode = goal.linkedWorkoutType {
                    parts.append(mode.displayName)
                }
                if let trackingSummary = goal.trackingSummary {
                    parts.append(trackingSummary)
                } else if let value = goal.targetValue {
                    parts.append("target \(value.formatted()) \(goal.targetUnit)")
                }
                if let supportingSummary = goal.supportingSummary,
                   supportingSummary != goal.trackingSummary {
                    parts.append(supportingSummary)
                }
                return parts.joined(separator: " • ")
            }
    }
}

enum WorkoutPlanSetupMode: Equatable {
    case proAI
    case manual

    var usesAI: Bool {
        self == .proAI
    }

    var shortTitle: String {
        switch self {
        case .proAI: "Trai Pro"
        case .manual: "Manual"
        }
    }
}

enum OnboardingWorkoutFocus: String, CaseIterable, Identifiable, Hashable {
    case strength
    case cardio
    case climbing
    case mobility
    case hiit
    case sport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .climbing: "Climbing"
        case .mobility: "Mobility"
        case .hiit: "HIIT"
        case .sport: "Sport"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: "Build muscle and get stronger"
        case .cardio: "Improve endurance"
        case .climbing: "Bouldering or rope work"
        case .mobility: "Yoga, Pilates, or mobility"
        case .hiit: "Intervals and conditioning"
        case .sport: "Train for an activity"
        }
    }

    var icon: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        case .climbing: "figure.climbing"
        case .mobility: "figure.yoga"
        case .hiit: "bolt.fill"
        case .sport: "sportscourt.fill"
        }
    }

    var workoutType: WorkoutPlanGenerationRequest.WorkoutType {
        switch self {
        case .strength: .strength
        case .cardio, .climbing: .cardio
        case .mobility: .flexibility
        case .hiit: .hiit
        case .sport: .mixed
        }
    }

    var cardioType: WorkoutPlanGenerationRequest.CardioType? {
        switch self {
        case .cardio: .anyCardio
        case .climbing: .climbing
        case .strength, .mobility, .hiit, .sport: nil
        }
    }

    var color: Color {
        switch self {
        case .strength: TraiColors.flame
        case .cardio: TraiColors.blaze
        case .climbing: TraiColors.coral
        case .mobility: Color.accentColor
        case .hiit: TraiColors.ember
        case .sport: TraiColors.brandAccent
        }
    }
}

enum OnboardingWorkoutSchedule: String, CaseIterable, Identifiable, Hashable {
    case twoDays
    case threeDays
    case fourDays
    case fiveDays
    case flexible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoDays: "2 days"
        case .threeDays: "3 days"
        case .fourDays: "4 days"
        case .fiveDays: "5 days"
        case .flexible: "Flexible"
        }
    }

    var subtitle: String {
        switch self {
        case .twoDays: "Minimal"
        case .threeDays: "Balanced"
        case .fourDays: "Structured"
        case .fiveDays: "Frequent"
        case .flexible: "Flexible"
        }
    }

    var days: Int? {
        switch self {
        case .twoDays: 2
        case .threeDays: 3
        case .fourDays: 4
        case .fiveDays: 5
        case .flexible: nil
        }
    }
}

enum OnboardingWorkoutDuration: Int, CaseIterable, Identifiable, Hashable {
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case sixtyMinutes = 60
    case ninetyMinutes = 90

    var id: Int { rawValue }
    var title: String { "\(rawValue) min" }

    var hint: String {
        switch self {
        case .thirtyMinutes: "quick"
        case .fortyFiveMinutes: "balanced"
        case .sixtyMinutes: "standard"
        case .ninetyMinutes: "long"
        }
    }
}

enum OnboardingWorkoutConstraint: String, CaseIterable, Identifiable, Hashable {
    case includeCardio
    case lowImpact
    case variety
    case shortSessions
    case injury
    case progressiveOverload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .includeCardio: "Cardio included"
        case .lowImpact: "Low impact"
        case .variety: "More variety"
        case .shortSessions: "Efficient sessions"
        case .injury: "Injury-aware"
        case .progressiveOverload: "Progression"
        }
    }

    var preferenceText: String {
        switch self {
        case .includeCardio: "Include cardio"
        case .lowImpact: "Keep it low impact"
        case .variety: "Add variety"
        case .shortSessions: "Keep sessions efficient"
        case .injury: "Work around an injury"
        case .progressiveOverload: "Prioritize progressive overload"
        }
    }

    var icon: String {
        switch self {
        case .includeCardio: "heart.fill"
        case .lowImpact: "figure.walk"
        case .variety: "shuffle"
        case .shortSessions: "timer"
        case .injury: "cross.case.fill"
        case .progressiveOverload: "chart.line.uptrend.xyaxis"
        }
    }
}

enum WorkoutPlanGoalPreset: String, CaseIterable, Identifiable, Hashable {
    case buildMuscle
    case getStronger
    case improveEndurance
    case stayConsistent
    case moveBetter
    case bodyComposition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildMuscle: "Build muscle"
        case .getStronger: "Get stronger"
        case .improveEndurance: "Endurance"
        case .stayConsistent: "Consistency"
        case .moveBetter: "Move better"
        case .bodyComposition: "Body composition"
        }
    }

    var goalText: String {
        switch self {
        case .buildMuscle: "Build muscle with a plan that supports progressive overload"
        case .getStronger: "Get stronger on key lifts and movement patterns"
        case .improveEndurance: "Improve endurance and conditioning"
        case .stayConsistent: "Train consistently each week"
        case .moveBetter: "Improve mobility, recovery, and movement quality"
        case .bodyComposition: "Support body composition goals with training that matches the nutrition plan"
        }
    }

    var icon: String {
        switch self {
        case .buildMuscle: "figure.strengthtraining.traditional"
        case .getStronger: "dumbbell.fill"
        case .improveEndurance: "figure.run"
        case .stayConsistent: "calendar.badge.checkmark"
        case .moveBetter: "figure.cooldown"
        case .bodyComposition: "chart.line.uptrend.xyaxis"
        }
    }

    var linkedWorkoutType: WorkoutMode? {
        switch self {
        case .buildMuscle, .getStronger: .strength
        case .improveEndurance: .cardio
        case .moveBetter: .mobility
        case .stayConsistent, .bodyComposition: nil
        }
    }

    var goalKind: WorkoutGoal.GoalKind {
        switch self {
        case .stayConsistent: .frequency
        default: .milestone
        }
    }

}

enum WorkoutPlanGenerationPriority: String, CaseIterable, Identifiable, Hashable {
    case muscle
    case strength
    case conditioning
    case bodyComposition
    case sportEvent
    case consistency
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muscle: "Build muscle"
        case .strength: "Get stronger"
        case .conditioning: "Conditioning"
        case .bodyComposition: "Lose fat"
        case .sportEvent: "Sport/event"
        case .consistency: "Consistency"
        case .recovery: "Move better"
        }
    }

    var icon: String {
        switch self {
        case .muscle: "figure.strengthtraining.traditional"
        case .strength: "dumbbell.fill"
        case .conditioning: "figure.run"
        case .bodyComposition: "chart.line.downtrend.xyaxis"
        case .sportEvent: "flag.checkered"
        case .consistency: "calendar.badge.checkmark"
        case .recovery: "figure.cooldown"
        }
    }

    var promptText: String {
        switch self {
        case .muscle: "Optimize the plan for muscle growth with enough volume and progression"
        case .strength: "Optimize the plan for strength progress on key lifts and movement patterns"
        case .conditioning: "Optimize the plan for conditioning and cardiovascular capacity"
        case .bodyComposition: "Optimize the plan for fat loss while preserving strength and lean muscle"
        case .sportEvent: "Optimize the plan around the user's sport, event, or performance target"
        case .consistency: "Optimize the plan for consistency and a week the user can realistically repeat"
        case .recovery: "Optimize the plan for recovery, joint friendliness, and sustainable effort"
        }
    }
}

enum WorkoutPlanGenerationStyle: String, CaseIterable, Identifiable, Hashable {
    case soreness
    case jointPain
    case missedWorkouts
    case boringRepetition
    case longSessions
    case poorRecovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soreness: "Too much soreness"
        case .jointPain: "Pain flare-ups"
        case .missedWorkouts: "Missed workouts"
        case .boringRepetition: "Boring repetition"
        case .longSessions: "Long sessions"
        case .poorRecovery: "Poor recovery"
        }
    }

    var icon: String {
        switch self {
        case .soreness: "bolt.heart.fill"
        case .jointPain: "cross.case.fill"
        case .missedWorkouts: "calendar.badge.exclamationmark"
        case .boringRepetition: "shuffle"
        case .longSessions: "timer"
        case .poorRecovery: "bed.double.fill"
        }
    }

    var promptText: String {
        switch self {
        case .soreness: "Protect the user from excessive soreness that makes the plan hard to repeat"
        case .jointPain: "Protect the user from knee, back, shoulder, or joint flare-ups"
        case .missedWorkouts: "Protect the user from an unrealistic plan that leads to missed workouts"
        case .boringRepetition: "Protect the user from boring repetition while keeping progression coherent"
        case .longSessions: "Protect the user from sessions that run too long for their schedule"
        case .poorRecovery: "Protect the user from poor recovery, burnout, and stacking too many hard days"
        }
    }
}

struct ManualWorkoutPlanDayDraft: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sessionType: WorkoutMode
    var focusAreasText: String
    var selectedMuscles: Set<LiveWorkout.MuscleGroup>

    init(
        id: UUID = UUID(),
        name: String,
        sessionType: WorkoutMode = .strength,
        focusAreasText: String = "",
        selectedMuscles: Set<LiveWorkout.MuscleGroup> = [.fullBody]
    ) {
        self.id = id
        self.name = name
        self.sessionType = sessionType
        self.focusAreasText = focusAreasText
        self.selectedMuscles = selectedMuscles
    }
}

struct OnboardingWorkoutPlanDraft: Equatable {
    var focuses: Set<OnboardingWorkoutFocus> = []
    var customFocus = ""
    var schedule: OnboardingWorkoutSchedule = .threeDays
    var duration: OnboardingWorkoutDuration = .fortyFiveMinutes
    var equipment: WorkoutPlanGenerationRequest.EquipmentAccess = .fullGym
    var experience: WorkoutPlanGenerationRequest.ExperienceLevel = .beginner
    var preferredSplit: WorkoutPlanGenerationRequest.PreferredSplit = .letTraiDecide
    var constraints: Set<OnboardingWorkoutConstraint> = []
    var goalPresets: Set<WorkoutPlanGoalPreset> = []
    var manualDays: [ManualWorkoutPlanDayDraft] = []
    var goalNotes = ""
    var rhythmNotes = ""
    var setupNotes = ""
    var preferenceNotes = ""
    var notes = ""
    var generationPriority: WorkoutPlanGenerationPriority?
    var generationStyle: WorkoutPlanGenerationStyle?
    var proCoachingNotes = ""

    var canGenerate: Bool {
        !focuses.isEmpty || !trimmedCustomFocus.isEmpty
    }

    var hasRequiredProTuning: Bool {
        proPersonalizationAnswerCount >= 3
    }

    var proPersonalizationAnswerCount: Int {
        trimmedProCoachingNotes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    func buildRequest(context: OnboardingWorkoutPlanUserContext) -> WorkoutPlanGenerationRequest {
        let selectedTypes = focuses
            .map(\.workoutType)
            .uniquedPreservingOrder
        let primaryType: WorkoutPlanGenerationRequest.WorkoutType = selectedTypes.count == 1
            ? (selectedTypes.first ?? .mixed)
            : .mixed
        let cardioTypes = cardioTypesForRequest()
        let preferenceText = preferenceSummary()

        return WorkoutPlanGenerationRequest(
            name: context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : context.name,
            age: context.age,
            gender: context.gender,
            goal: context.goal,
            activityLevel: context.activityLevel,
            workoutType: primaryType,
            selectedWorkoutTypes: selectedTypes.isEmpty ? nil : selectedTypes,
            experienceLevel: experience,
            equipmentAccess: equipment,
            availableDays: schedule.days,
            timePerWorkout: duration.rawValue,
            preferredSplit: preferredSplit,
            cardioTypes: cardioTypes.isEmpty ? nil : cardioTypes,
            customWorkoutType: trimmedCustomFocus.isEmpty ? nil : trimmedCustomFocus,
            customExperience: nil,
            customEquipment: nil,
            customCardioType: nil,
            specificGoals: specificGoalsForRequest(),
            weakPoints: nil,
            injuries: injuriesForRequest(),
            preferences: preferenceText,
            conversationContext: conversationContext(context: context)
        )
    }

    func applyPreferences(to profile: UserProfile, generatedPlan: WorkoutPlan?) {
        profile.preferredWorkoutDays = generatedPlan?.daysPerWeek ?? schedule.days ?? profile.preferredWorkoutDays
        profile.workoutTimePerSession = duration.rawValue
        profile.workoutEquipment = equipment
        profile.workoutExperience = experience
    }

    mutating func applyImplicitProGenerationTuningIfNeeded() {
        if generationPriority == nil {
            generationPriority = inferredGenerationPriority
        }
        if generationStyle == nil {
            generationStyle = inferredGenerationStyle
        }
    }

    private func cardioTypesForRequest() -> [WorkoutPlanGenerationRequest.CardioType] {
        var values = focuses.compactMap(\.cardioType).uniquedPreservingOrder
        if constraints.contains(.includeCardio), !values.contains(.anyCardio) {
            values.append(.anyCardio)
        }
        return values
    }

    private func preferenceSummary() -> String? {
        var parts = constraints
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.preferenceText)
        for note in [goalNotes, rhythmNotes, setupNotes, preferenceNotes, proCoachingNotes, notes] {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty {
                parts.append(trimmedNote)
            }
        }
        if let generationPriority {
            parts.append(generationPriority.promptText)
        }
        if let generationStyle {
            parts.append(generationStyle.promptText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func specificGoalsForRequest() -> [String]? {
        let presetGoals = goalPresets
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.goalText)
        let values = (presetGoals + [
            customFocus,
            goalNotes,
            rhythmNotes,
            setupNotes,
            preferenceNotes,
            proCoachingNotes,
            notes
        ] + [
            generationPriority?.promptText,
            generationStyle?.promptText
        ].compactMap { $0 })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func injuriesForRequest() -> String? {
        if constraints.contains(.injury) {
            return "Work around an injury"
        }
        if constraints.contains(.lowImpact) {
            return "Prefer lower-impact training"
        }
        return nil
    }

    private func conversationContext(context userContext: OnboardingWorkoutPlanUserContext) -> [String] {
        let focusText = focusSummary()
        var context = [
            "Requested training styles: \(focusText)",
            "Weekly schedule: \(schedule.title)",
            "Session length: \(duration.title)",
            "Equipment: \(equipment.displayName)",
            "Training background: \(experience.displayName)",
            "Preferred split: \(preferredSplit.displayName)"
        ]

        if !goalPresets.isEmpty {
            let goals = goalPresets
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.goalText)
                .joined(separator: "; ")
            context.append("Workout goals selected in plan setup: \(goals)")
        }

        if let preferenceText = preferenceSummary() {
            context.append("Preferences and constraints: \(preferenceText)")
        }

        context.append(contentsOf: userContext.nutritionContext.map { "Nutrition context: \($0)" })
        context.append(contentsOf: userContext.memoryContext.map { "Known user context: \($0)" })
        context.append(contentsOf: userContext.activeWorkoutGoalContext.map { "Existing workout goal: \($0)" })

        appendLabeledNote("Custom focus", customFocus, to: &context)
        appendLabeledNote("Goal notes", goalNotes, to: &context)
        appendLabeledNote("Schedule notes", rhythmNotes, to: &context)
        appendLabeledNote("Equipment/background notes", setupNotes, to: &context)
        appendLabeledNote("Preference notes", preferenceNotes, to: &context)
        appendLabeledNote("Personalization brief (highest priority)", proCoachingNotes, to: &context)
        appendLabeledNote("Review notes", notes, to: &context)

        return context
    }

    private func appendLabeledNote(_ label: String, _ value: String, to context: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.append("\(label): \(trimmed)")
    }

    private var trimmedCustomFocus: String {
        customFocus.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProCoachingNotes: String {
        proCoachingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusSummary() -> String {
        var values = focuses.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if !trimmedCustomFocus.isEmpty {
            values.append(trimmedCustomFocus)
        }
        return values.isEmpty ? "Custom workout plan" : values.joined(separator: ", ")
    }

    private var inferredGenerationPriority: WorkoutPlanGenerationPriority {
        if goalPresets.contains(.getStronger) {
            return .strength
        }
        if goalPresets.contains(.buildMuscle) || goalPresets.contains(.bodyComposition) {
            return .muscle
        }
        if constraints.contains(.lowImpact) || constraints.contains(.injury) || goalPresets.contains(.moveBetter) {
            return .recovery
        }
        return .consistency
    }

    private var inferredGenerationStyle: WorkoutPlanGenerationStyle {
        if constraints.contains(.variety) || schedule == .flexible {
            return .boringRepetition
        }
        if constraints.contains(.progressiveOverload) || experience == .advanced {
            return .missedWorkouts
        }
        if experience == .beginner || constraints.contains(.shortSessions) {
            return .longSessions
        }
        return .poorRecovery
    }

    func buildManualPlan(context: OnboardingWorkoutPlanUserContext) -> WorkoutPlan {
        let days = normalizedManualDays()
        let templates = days.enumerated().map { index, day in
            let focusAreas = sanitizedFocusAreas(from: day.focusAreasText)
            let targets = targetGroups(for: day)
            return WorkoutPlan.WorkoutTemplate(
                name: day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Workout Day \(index + 1)"
                    : day.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionType: day.sessionType,
                focusAreas: focusAreas.isEmpty ? targets : focusAreas,
                targetMuscleGroups: day.sessionType.supportsMuscleTargets ? targets : [],
                exercises: [],
                estimatedDurationMinutes: duration.rawValue,
                order: index,
                notes: nil
            )
        }

        return WorkoutPlan(
            splitType: preferredSplit == .letTraiDecide ? .custom : preferredSplit.splitType,
            daysPerWeek: max(templates.count, schedule.days ?? templates.count),
            templates: templates,
            planIntent: WorkoutPlan.PlanIntent(
                primaryFocus: focusSummary(),
                supportingFocuses: [],
                sessionAllocation: "\(templates.count) manually configured sessions",
                honoredInputs: [
                    "\(schedule.title)",
                    "\(duration.title)",
                    "\(equipment.displayName)"
                ],
                avoided: [],
                summary: "A manually configured weekly plan."
            ),
            rationale: "A manually configured plan for \(context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "your" : "\(context.name)'s") weekly training.",
            guidelines: [
                "Start with conservative effort for the first week.",
                "Adjust exercises and muscle targets from the plan editor as your routine changes.",
                "Use Trai Pro when you want Trai to build, explain, and update the plan from your progress."
            ],
            progressionStrategy: .defaultStrategy,
            modalityProgression: WorkoutPlan.ModalityProgression(
                focus: .consistency,
                weeklyProgression: "Keep the schedule repeatable, then adjust the plan as training data builds.",
                targets: []
            ),
            warnings: nil
        )
    }

    private func normalizedManualDays() -> [ManualWorkoutPlanDayDraft] {
        if !manualDays.isEmpty {
            return manualDays
        }
        return Self.defaultManualDays(for: preferredSplit == .letTraiDecide ? .fullBody : preferredSplit, count: schedule.days ?? 3)
    }

    static func defaultManualDays(
        for split: WorkoutPlanGenerationRequest.PreferredSplit,
        count: Int
    ) -> [ManualWorkoutPlanDayDraft] {
        let boundedCount = max(1, min(count, 7))
        let days: [ManualWorkoutPlanDayDraft]
        switch split {
        case .upperLower:
            days = [
                ManualWorkoutPlanDayDraft(name: "Upper Body", selectedMuscles: [.chest, .back, .shoulders, .biceps, .triceps, .forearms]),
                ManualWorkoutPlanDayDraft(name: "Lower Body", selectedMuscles: [.quads, .hamstrings, .glutes, .calves]),
                ManualWorkoutPlanDayDraft(name: "Upper Body", selectedMuscles: [.chest, .back, .shoulders, .biceps, .triceps, .forearms]),
                ManualWorkoutPlanDayDraft(name: "Lower Body", selectedMuscles: [.quads, .hamstrings, .glutes, .calves]),
                ManualWorkoutPlanDayDraft(name: "Full Body", selectedMuscles: [.fullBody])
            ]
        case .pushPullLegs:
            days = [
                ManualWorkoutPlanDayDraft(name: "Push", selectedMuscles: Set(LiveWorkout.MuscleGroup.pushMuscles)),
                ManualWorkoutPlanDayDraft(name: "Pull", selectedMuscles: Set(LiveWorkout.MuscleGroup.pullMuscles)),
                ManualWorkoutPlanDayDraft(name: "Legs", selectedMuscles: Set(LiveWorkout.MuscleGroup.legMuscles)),
                ManualWorkoutPlanDayDraft(name: "Upper", selectedMuscles: [.chest, .back, .shoulders, .biceps, .triceps, .forearms]),
                ManualWorkoutPlanDayDraft(name: "Lower", selectedMuscles: [.quads, .hamstrings, .glutes, .calves])
            ]
        case .broSplit:
            days = [
                ManualWorkoutPlanDayDraft(name: "Chest", selectedMuscles: [.chest]),
                ManualWorkoutPlanDayDraft(name: "Back", selectedMuscles: [.back]),
                ManualWorkoutPlanDayDraft(name: "Legs", selectedMuscles: [.quads, .hamstrings, .glutes, .calves]),
                ManualWorkoutPlanDayDraft(name: "Shoulders", selectedMuscles: [.shoulders]),
                ManualWorkoutPlanDayDraft(name: "Arms", selectedMuscles: [.biceps, .triceps, .forearms])
            ]
        case .fullBody, .letTraiDecide:
            days = (1...max(boundedCount, 1)).map { index in
                ManualWorkoutPlanDayDraft(
                    name: boundedCount == 1 ? "Full Body" : "Full Body \(index)",
                    selectedMuscles: [.fullBody]
                )
            }
        }

        if days.count >= boundedCount {
            return Array(days.prefix(boundedCount))
        }

        var expanded = days
        while expanded.count < boundedCount {
            expanded.append(
                ManualWorkoutPlanDayDraft(
                    name: "Workout Day \(expanded.count + 1)",
                    selectedMuscles: [.fullBody]
                )
            )
        }
        return expanded
    }

    private func sanitizedFocusAreas(from text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .components(separatedBy: ",")
            .compactMap { raw in
                let normalized = raw
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .lowercased()
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
                return normalized
            }
    }

    private func targetGroups(for day: ManualWorkoutPlanDayDraft) -> [String] {
        guard day.sessionType.supportsMuscleTargets else { return [] }
        let selected = day.selectedMuscles.isEmpty ? Set([LiveWorkout.MuscleGroup.fullBody]) : day.selectedMuscles
        let ordered = LiveWorkout.MuscleGroup.allCases
            .filter { selected.contains($0) }
            .map(\.rawValue)
        if ordered.count > 1 {
            return ordered.filter { $0 != LiveWorkout.MuscleGroup.fullBody.rawValue }
        }
        return ordered.isEmpty ? [LiveWorkout.MuscleGroup.fullBody.rawValue] : ordered
    }
}

private enum WorkoutPlanSetupStep: Int, CaseIterable, Identifiable {
    case focus
    case goals
    case schedule
    case setup
    case preferences
    case tuning
    case structure
    case review

    var id: Int { rawValue }

    static func steps(for mode: WorkoutPlanSetupMode) -> [WorkoutPlanSetupStep] {
        switch mode {
        case .proAI:
            [.focus, .goals, .schedule, .setup, .tuning]
        case .manual:
            [.focus, .goals, .schedule, .setup, .preferences, .structure, .review]
        }
    }

    func title(for mode: WorkoutPlanSetupMode) -> String {
        switch self {
        case .focus:
            mode == .proAI ? "What should Trai build around?" : "What should your plan include?"
        case .goals:
            "What are you training for?"
        case .schedule:
            "How often and how long?"
        case .setup:
            mode == .proAI ? "What should Trai plan around?" : "Set up your plan"
        case .preferences:
            mode == .proAI ? "Anything I should work around?" : "Add any details"
        case .tuning:
            "Tell Trai what matters"
        case .structure:
            "Choose your plan structure"
        case .review:
            mode == .proAI ? "Ready for Trai to build it" : "Ready to save your plan"
        }
    }

    var accentColor: Color {
        switch self {
        case .focus: TraiColors.flame
        case .goals: TraiColors.brandAccent
        case .schedule: TraiColors.blaze
        case .setup: TraiColors.coral
        case .preferences: Color.accentColor
        case .tuning: TraiColors.brandAccent
        case .structure: TraiColors.brandAccent
        case .review: TraiColors.brandAccent
        }
    }
}

private enum WorkoutPlanSetupNavigationDirection {
    case forward
    case backward
}

private struct GeneratedPlanSignalChip {
    let icon: String
    let title: String
}

private struct ProPersonalizationQuestion {
    let label: String
    let prompt: String
    let placeholder: String
    let suggestions: [(title: String, text: String)]
}

struct OnboardingWorkoutPlanSetupView: View {
    @Binding var draft: OnboardingWorkoutPlanDraft

    let context: OnboardingWorkoutPlanUserContext
    let aiService: AIService
    var mode: WorkoutPlanSetupMode = .proAI
    var showsProForkBeforeReview = false
    var canAccessAIFeatures = true
    var advancePastSetupAfterManualFork = false
    var onProForkRequired: (() -> Void)?
    let onComplete: (WorkoutPlan, [WorkoutGoal]) -> Void
    let onBack: () -> Void

    @State private var isGenerating = false
    @State private var generationNote: String?
    @State private var generatedPlanForReview: WorkoutPlan?
    @State private var generatedPlanGoalsForReview: [WorkoutGoal] = []
    @State private var generatedPlanUsedFallback = false
    @State private var currentStep: WorkoutPlanSetupStep = .focus
    @State private var navigationDirection: WorkoutPlanSetupNavigationDirection = .forward
    @State private var showingGeneratedPlanChat = false
    @State private var generatedPlanRefinementText = ""
    @State private var generatedPlanChatPrompt: String?
    @State private var proBriefInput = ""
    @State private var proPersonalizationQuestionIndex = 0
    @State private var dynamicProPersonalizationQuestions: [ProPersonalizationQuestion] = []
    @State private var isGeneratingProPersonalizationQuestion = false
    @State private var hasQueuedProPlanGeneration = false
    @State private var generationStartedAt: Date?
    @State private var generationStatusTitle = "Creating your plan"
    @State private var showingManualDayEditor = false
    @State private var editingManualDayID: UUID?
    @State private var editorDayName = ""
    @State private var editorSessionType: WorkoutMode = .strength
    @State private var editorFocusAreasText = ""
    @State private var editorSelectedMuscles: Set<LiveWorkout.MuscleGroup> = [.fullBody]

    @FocusState private var isGeneratedPlanInputFocused: Bool
    @FocusState private var isProBriefInputFocused: Bool

    var body: some View {
        ZStack {
            OnboardingAmbientBackground()

            if let generatedPlanForReview {
                generatedPlanWorkspace(generatedPlanForReview)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 18) {
                            topNavigationRow
                            stepProgress
                            header
                            stepContent
                                .id(currentStep)
                                .transition(stepTransition)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, isProTuningChatStep ? 158 : 148)
                    }
                    .scrollIndicators(.hidden)

                    bottomBar
                }
            }
        }
        .traiSheetBranding()
        .onChange(of: advancePastSetupAfterManualFork, initial: true) { _, shouldAdvance in
            guard shouldAdvance, mode == .manual, currentStep == .setup else { return }
            navigationDirection = .forward
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = .preferences
            }
        }
        .sheet(isPresented: $showingManualDayEditor) {
            WorkoutDayEditorSheet(
                title: editingManualDayID == nil ? "Add Workout Day" : "Edit Workout Day",
                confirmTitle: editingManualDayID == nil ? "Add" : "Save",
                dayName: $editorDayName,
                sessionType: $editorSessionType,
                focusAreasText: $editorFocusAreasText,
                selectedMuscles: $editorSelectedMuscles,
                onCancel: { showingManualDayEditor = false },
                onConfirm: saveManualDayEditor
            )
        }
        .sheet(isPresented: $showingGeneratedPlanChat) {
            if let generatedPlanForReview {
                WorkoutPlanChatFlow(
                    isOnboarding: true,
                    currentPlanToEdit: generatedPlanForReview,
                    generatedPlanGoals: generatedPlanGoalsForReview,
                    initialRefinementPrompt: generatedPlanChatPrompt,
                    onCompleteWithGoals: { plan, goals in
                        generatedPlanGoalsForReview = goals
                        onComplete(plan, goals)
                    }
                )
                .traiSheetBranding()
            }
        }
        .onChange(of: mode) { oldMode, newMode in
            guard oldMode == .proAI, newMode == .manual, currentStep == .preferences else { return }
            navigationDirection = .forward
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = .structure
            }
        }
        .onChange(of: showingGeneratedPlanChat) { _, isShowing in
            if !isShowing {
                generatedPlanChatPrompt = nil
            }
        }
    }

    private func generatedPlanWorkspace(_ plan: WorkoutPlan) -> some View {
        WorkoutPlanChatFlow(
            isOnboarding: true,
            embedded: true,
            currentPlanToEdit: plan,
            existingPlanIntroMessage: generatedPlanIntroMessage(for: plan),
            existingPlanAcceptTitle: "Save Plan",
            generatedPlanGoals: generatedPlanGoalsForReview,
            showsGeneratedOnboardingHeader: false,
            onCompleteWithGoals: { plan, goals in
                generatedPlanGoalsForReview = goals
                onComplete(plan, goals)
            }
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private var header: some View {
        if isProTuningChatStep {
            proTuningChatHeader
        } else {
            OnboardingTraiHeader(
                title: headerTitle,
                lensSize: isGenerating ? 68 : 52,
                lensState: headerLensState,
                lensBreathes: isGenerating
            )
        }
    }

    private var proTuningChatHeader: some View {
        HStack(spacing: 10) {
            TraiLensView(size: 34, state: .idle, palette: .energy, breathes: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("Trai")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Workout plan setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        if isGenerating {
            return generationStatusTitle
        }
        if currentStep == .review {
            if generatedPlanForReview != nil {
                return "Your plan is ready"
            }
        }
        return currentStep.title(for: mode)
    }

    private var headerLensState: TraiLensState {
        if isGenerating {
            return .thinking
        }
        if generatedPlanForReview != nil {
            return .answering
        }
        return .idle
    }

    private var topNavigationRow: some View {
        HStack {
            if currentStep != .focus {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.traiLabel(14))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(height: currentStep == .focus ? 0 : 24)
        .opacity(currentStep == .focus ? 0 : 1)
    }

    private var stepProgress: some View {
        OnboardingProgressDots(
            currentStep: currentStepIndex,
            totalSteps: steps.count
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout plan setup progress")
        .accessibilityValue("Step \(currentStepIndex + 1) of \(steps.count)")
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: navigationDirection == .forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigationDirection == .forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .focus:
            focusSection
        case .goals:
            goalsSection
        case .schedule:
            VStack(spacing: 12) {
                scheduleSection
                durationSection
                rhythmNotesSection
            }
        case .setup:
            VStack(spacing: 12) {
                equipmentSection
                experienceSection
                setupNotesSection
            }
        case .preferences:
            if mode == .proAI {
                constraintsSection
            } else {
                VStack(spacing: 12) {
                    constraintsSection
                    notesSection
                }
            }
        case .tuning:
            if isGenerating {
                generatingPage
            } else {
                proTuningSection
            }
        case .structure:
            manualStructureSection
                .onAppear {
                    if draft.preferredSplit == .letTraiDecide {
                        draft.preferredSplit = .fullBody
                    }
                }
        case .review:
            if isGenerating {
                generatingPage
            } else {
                reviewSection
            }
        }
    }

    private var steps: [WorkoutPlanSetupStep] {
        WorkoutPlanSetupStep.steps(for: mode)
    }

    private var currentStepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }

    private var usesAI: Bool {
        mode.usesAI
    }

    private var isProTuningChatStep: Bool {
        currentStep == .tuning && usesAI && generatedPlanForReview == nil && !isGenerating
    }

    private var focusSection: some View {
        setupSection(title: nil) {
            VStack(spacing: 14) {
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(OnboardingWorkoutFocus.allCases) { focus in
                            OnboardingChoiceCard(
                                title: focus.title,
                                hint: nil,
                                iconName: focus.icon,
                                tint: focus.color,
                                isSelected: draft.focuses.contains(focus),
                                minHeight: 96
                            ) {
                                toggleFocus(focus)
                            }
                        }
                    }
                }

                customInstructionsField(
                    title: "Add your own focus",
                    placeholder: "Powerlifting, tennis, soccer, marathon...",
                    text: $draft.customFocus,
                    minHeight: 64
                )
            }
        }
    }

    private var goalsSection: some View {
        VStack(spacing: 14) {
            setupSection(title: nil) {
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(WorkoutPlanGoalPreset.allCases) { preset in
                            OnboardingChoiceCard(
                                title: preset.title,
                                hint: nil,
                                iconName: preset.icon,
                                tint: TraiColors.brandAccent,
                                isSelected: draft.goalPresets.contains(preset),
                                minHeight: 84
                            ) {
                                HapticManager.lightTap()
                                if draft.goalPresets.contains(preset) {
                                    draft.goalPresets.remove(preset)
                                } else {
                                    draft.goalPresets.insert(preset)
                                }
                            }
                        }
                    }
                }
            }

            customInstructionsField(
                title: "Add a specific goal",
                placeholder: "First pull-up, stronger squat, climb V5, run a 10K...",
                text: $draft.goalNotes,
                minHeight: 72
            )
        }
    }

    private var scheduleSection: some View {
        setupSection(title: "Weekly rhythm") {
            weeklyRhythmControl
        }
    }

    private var durationSection: some View {
        setupSection(title: "Session length") {
            sessionLengthControl
        }
    }

    private var equipmentSection: some View {
        setupSection(title: "Equipment") {
            optionGrid(WorkoutPlanGenerationRequest.EquipmentAccess.allCases, selection: $draft.equipment, minHeight: 76) { equipment in
                OptionContent(
                    title: equipment.displayName,
                    subtitle: equipment.description,
                    icon: equipment.iconName,
                    tint: equipmentTint(for: equipment)
                )
            }
        }
    }

    private var experienceSection: some View {
        setupSection(title: "Training background") {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(WorkoutPlanGenerationRequest.ExperienceLevel.allCases) { experience in
                        OnboardingChoiceCard(
                            title: experience.displayName,
                            hint: nil,
                            iconName: experience.iconName,
                            tint: experienceTint(for: experience),
                            isSelected: draft.experience == experience,
                            minHeight: 76
                        ) {
                            draft.experience = experience
                        }
                    }
                }
            }
        }
    }

    private var manualStructureSection: some View {
        VStack(spacing: 14) {
            setupSection(title: "Pick a preset") {
                GlassEffectContainer(spacing: 10) {
                    FlowLayout(spacing: 8) {
                        ForEach(manualSplitOptions) { split in
                            OnboardingChip(
                                title: split.shortDisplayName,
                                icon: split.iconName,
                                isSelected: normalizedManualSplit == split
                            ) {
                                HapticManager.lightTap()
                                draft.preferredSplit = split
                                draft.manualDays = OnboardingWorkoutPlanDraft.defaultManualDays(
                                    for: split,
                                    count: concreteScheduleDays
                                )
                            }
                        }
                    }
                }
            }

            setupSection(title: "Workout days") {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        rhythmAdjustButton(systemName: "minus") {
                            adjustManualDayCount(by: -1)
                        }
                        .disabled(manualDaysForDisplay.count <= 1)

                        VStack(spacing: 4) {
                            Text("\(manualDaysForDisplay.count)")
                                .font(.traiBold(34))
                                .monospacedDigit()

                            Text("days per week")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        rhythmAdjustButton(systemName: "plus") {
                            adjustManualDayCount(by: 1)
                        }
                        .disabled(manualDaysForDisplay.count >= 7)
                    }
                    .padding(14)
                    .onboardingTraiResponseCard(cornerRadius: 18)

                    VStack(spacing: 8) {
                        ForEach(manualDaysForDisplay.indices, id: \.self) { index in
                            manualPlanDayRow(index: index, day: manualDaysForDisplay[index])
                        }
                    }

                    Button {
                        presentAddManualDay()
                    } label: {
                        Label("Add Workout Day", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true))
                }
            }
        }
    }

    private var manualSplitOptions: [WorkoutPlanGenerationRequest.PreferredSplit] {
        [.fullBody, .upperLower, .pushPullLegs, .broSplit]
    }

    private var normalizedManualSplit: WorkoutPlanGenerationRequest.PreferredSplit {
        draft.preferredSplit == .letTraiDecide ? .fullBody : draft.preferredSplit
    }

    private var manualDaysForDisplay: [ManualWorkoutPlanDayDraft] {
        if !draft.manualDays.isEmpty {
            return draft.manualDays
        }
        return OnboardingWorkoutPlanDraft.defaultManualDays(
            for: normalizedManualSplit,
            count: concreteScheduleDays
        )
    }

    private func manualPlanDayRow(index: Int, day: ManualWorkoutPlanDayDraft) -> some View {
        Button {
            presentEditManualDay(day)
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Label(day.sessionType.displayName, systemImage: day.sessionType.iconName)
                        Text("•")
                        Text(manualDayFocusSummary(day))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .onboardingTintedGlass(
            tint: TraiColors.brandAccent,
            isSelected: false,
            cornerRadius: 14,
            isInteractive: false
        )
    }

    private func manualDayFocusSummary(_ day: ManualWorkoutPlanDayDraft) -> String {
        if day.sessionType.supportsMuscleTargets {
            let muscles = day.selectedMuscles.isEmpty ? Set([LiveWorkout.MuscleGroup.fullBody]) : day.selectedMuscles
            return LiveWorkout.MuscleGroup.allCases
                .filter { muscles.contains($0) }
                .map(\.displayName)
                .joined(separator: ", ")
        }

        let trimmed = day.focusAreasText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(draft.duration.title) session" : trimmed
    }

    private func adjustManualDayCount(by delta: Int) {
        HapticManager.lightTap()
        var days = manualDaysForDisplay
        if delta > 0 {
            days.append(
                ManualWorkoutPlanDayDraft(
                    name: "Workout Day \(days.count + 1)",
                    selectedMuscles: [.fullBody]
                )
            )
        } else if days.count > 1 {
            days.removeLast()
        }
        draft.manualDays = days
    }

    private func presentAddManualDay() {
        editingManualDayID = nil
        editorDayName = ""
        editorSessionType = .strength
        editorFocusAreasText = ""
        editorSelectedMuscles = [.fullBody]
        showingManualDayEditor = true
    }

    private func presentEditManualDay(_ day: ManualWorkoutPlanDayDraft) {
        editingManualDayID = day.id
        editorDayName = day.name
        editorSessionType = day.sessionType
        editorFocusAreasText = day.focusAreasText
        editorSelectedMuscles = day.selectedMuscles.isEmpty ? [.fullBody] : day.selectedMuscles
        showingManualDayEditor = true
    }

    private func saveManualDayEditor() {
        let fallbackName = editingManualDayID == nil
            ? "Workout Day \(manualDaysForDisplay.count + 1)"
            : "Workout Day"
        let day = ManualWorkoutPlanDayDraft(
            id: editingManualDayID ?? UUID(),
            name: editorDayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallbackName
                : editorDayName,
            sessionType: editorSessionType,
            focusAreasText: editorFocusAreasText,
            selectedMuscles: editorSessionType.supportsMuscleTargets ? editorSelectedMuscles : []
        )

        var days = manualDaysForDisplay
        if let editingManualDayID,
           let index = days.firstIndex(where: { $0.id == editingManualDayID }) {
            days[index] = day
        } else {
            days.append(day)
        }
        draft.manualDays = days
        showingManualDayEditor = false
    }

    private var constraintsSection: some View {
        setupSection(title: "Tailor the plan") {
            FlowLayout(spacing: 8) {
                ForEach(OnboardingWorkoutConstraint.allCases) { constraint in
                    OnboardingChip(
                        title: constraint.title,
                        icon: constraint.icon,
                        isSelected: draft.constraints.contains(constraint)
                    ) {
                        HapticManager.lightTap()
                        if draft.constraints.contains(constraint) {
                            draft.constraints.remove(constraint)
                        } else {
                            draft.constraints.insert(constraint)
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        customInstructionsField(
            title: "Tell Trai exactly what you want",
            placeholder: "Favorite lifts, injuries, sport goals, exercises to include or avoid...",
            text: $draft.preferenceNotes
        )
    }

    private var proTuningSection: some View {
        VStack(spacing: 14) {
            ForEach(Array(proPersonalizationQuestions.enumerated()), id: \.offset) { index, question in
                if index <= proVisibleQuestionIndex {
                    proAssistantMessageRow(question.prompt)

                    if proPersonalizationAnswers.indices.contains(index) {
                        HStack {
                            Spacer(minLength: 40)
                            TraiUserTextBubble(text: proPersonalizationAnswers[index])
                        }
                    }
                }
            }

            if isGeneratingProPersonalizationQuestion {
                proAssistantMessageRow("Let me check what matters most before I ask the last thing.")
                    .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.24), value: draft.trimmedProCoachingNotes)
        .animation(.easeInOut(duration: 0.24), value: isGeneratingProPersonalizationQuestion)
        .onAppear {
            prepareProPersonalizationIfNeeded()
        }
    }

    private var proPersonalizationAnswers: [String] {
        draft.trimmedProCoachingNotes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                guard let separator = line.firstIndex(of: ":") else { return line }
                return String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private var proVisibleQuestionIndex: Int {
        min(
            proPersonalizationQuestionIndex,
            proPersonalizationQuestions.count - 1
        )
    }

    private var hasAnsweredAllProPersonalizationQuestions: Bool {
        draft.proPersonalizationAnswerCount >= proPersonalizationTargetQuestionCount
    }

    private var currentProPersonalizationQuestion: ProPersonalizationQuestion? {
        guard !hasAnsweredAllProPersonalizationQuestions else { return nil }
        guard draft.proPersonalizationAnswerCount < proPersonalizationQuestions.count else { return nil }
        guard proPersonalizationQuestions.indices.contains(proVisibleQuestionIndex) else { return nil }
        return proPersonalizationQuestions[proVisibleQuestionIndex]
    }

    private var proPersonalizationQuestions: [ProPersonalizationQuestion] {
        baseProPersonalizationQuestions + dynamicProPersonalizationQuestions
    }

    private var proPersonalizationTargetQuestionCount: Int {
        3
    }

    private var maxDynamicProPersonalizationQuestionCount: Int {
        max(0, proPersonalizationTargetQuestionCount - baseProPersonalizationQuestions.count)
    }

    private var baseProPersonalizationQuestions: [ProPersonalizationQuestion] {
        if selectedFocusesForPersonalization.count > 1 {
            return [
                multiFocusBalanceQuestion,
                secondMixedFocusQuestion
            ]
        }

        switch primaryFocusForPersonalization {
        case .strength:
            return [
                strengthStructureQuestion
            ]
        case .cardio:
            return [
                cardioProgressionQuestion
            ]
        case .climbing, .sport:
            return [
                sportSupportQuestion
            ]
        case .mobility:
            return [
                mobilityTargetQuestion
            ]
        case .hiit:
            return [
                conditioningStyleQuestion
            ]
        case nil:
            return [
                multiFocusBalanceQuestion
            ]
        }
    }

    private var secondMixedFocusQuestion: ProPersonalizationQuestion {
        if shouldAskStrengthSplitInMixedPlan {
            return strengthStructureQuestion
        }
        return focusOutcomeQuestion
    }

    private var shouldAskStrengthSplitInMixedPlan: Bool {
        guard draft.focuses.contains(.strength) else { return false }
        return isStrengthLeadingForPersonalization ||
            draft.goalPresets.contains(.buildMuscle) ||
            draft.goalPresets.contains(.getStronger)
    }

    private var selectedFocusesForPersonalization: [OnboardingWorkoutFocus] {
        OnboardingWorkoutFocus.allCases.filter { draft.focuses.contains($0) }
    }

    private var primaryFocusForPersonalization: OnboardingWorkoutFocus? {
        selectedFocusesForPersonalization.first
    }

    private var proPersonalizationContextText: String {
        [
            draft.trimmedProCoachingNotes,
            draft.goalNotes,
            draft.rhythmNotes,
            draft.setupNotes,
            draft.preferenceNotes,
            draft.notes
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private var isCardioSupportOnlyForPersonalization: Bool {
        let text = proPersonalizationContextText
        let supportSignals = [
            "cardio supports",
            "supporting cardio",
            "cardio finisher",
            "short finisher",
            "easy finisher",
            "after one lift",
            "after a lift",
            "after strength",
            "after lifting",
            "at the end",
            "not a full cardio day",
            "not a cardio day"
        ]
        return supportSignals.contains { text.contains($0) }
    }

    private var isStrengthLeadingForPersonalization: Bool {
        let text = proPersonalizationContextText
        return text.contains("strength leads") ||
            text.contains("strength the main") ||
            text.contains("strength the priority") ||
            text.contains("strength-focused") ||
            (draft.focuses.contains(.strength) && isCardioSupportOnlyForPersonalization)
    }

    private var proReadyToBuildMessage: String {
        if selectedFocusesForPersonalization.count > 1 {
            return "Perfect. Now I can balance the week, build the right goals, and decide what each session should do."
        }
        switch primaryFocusForPersonalization {
        case .strength:
            return "Perfect. Now I can build the split, goals, exercise choices, and recovery around what you actually want."
        case .cardio:
            return "Perfect. Now I can build the progression, hard/easy rhythm, and recovery around that."
        case .climbing, .sport:
            return "Perfect. Now I can build training that supports performance without interfering with it."
        case .mobility:
            return "Perfect. Now I can build mobility and recovery work around the areas that matter."
        case .hiit:
            return "Perfect. Now I can build conditioning that fits your intensity, recovery, and schedule."
        case nil:
            return "Perfect. Now I can build the week around what matters."
        }
    }

    private func proAssistantMessageRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var personalizationPlaceholder: String {
        currentProPersonalizationQuestion?.placeholder ?? "Tell Trai what should shape the plan..."
    }

    private var proPersonalizationSuggestions: [(title: String, text: String)] {
        currentProPersonalizationQuestion?.suggestions ?? []
    }

    private var focusTitleListForPersonalization: String {
        let titles = selectedFocusesForPersonalization.map(\.title)
        guard !titles.isEmpty else { return "your training" }
        if titles.count == 1 { return titles[0].lowercased() }
        if titles.count == 2 {
            return titles.map { $0.lowercased() }.joined(separator: " and ")
        }
        return titles.dropLast().joined(separator: ", ").lowercased() + ", and " + (titles.last?.lowercased() ?? "")
    }

    private var multiFocusBalanceQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Focus balance",
            prompt: "How should I balance \(focusTitleListForPersonalization) in your week?",
            placeholder: "Ex: strength leads, cardio supports, keep one recovery day...",
            suggestions: focusBalanceSuggestions
        )
    }

    private var strengthStructureQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Split direction",
            prompt: "Do you want full-body days or a split?",
            placeholder: "Ex: upper/lower, legs twice, full body...",
            suggestions: [
                (title: "Upper/lower", text: "Use an upper/lower style split."),
                (title: "Legs twice", text: "Make sure legs get two focused exposures each week."),
                (title: "Push/pull/legs", text: "Use a push, pull, legs style split if it fits."),
                (title: "Body-part focus", text: "Use a body-part focused split if it fits."),
                (title: "Full body", text: "Use full-body sessions across the week.")
            ]
        )
    }

    private var cardioProgressionQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Cardio target",
            prompt: "What kind of cardio progress should this build toward?",
            placeholder: "Ex: run farther, faster 5K, better conditioning...",
            suggestions: [
                (title: "Run farther", text: "I want to build distance without burning out."),
                (title: "Faster pace", text: "I want to improve pace and speed."),
                (title: "Better conditioning", text: "I want better all-around conditioning."),
                (title: "Event prep", text: "I am working toward a race or event."),
                (title: "Low impact", text: "Keep cardio lower impact.")
            ]
        )
    }

    private var cardioRhythmQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Cardio rhythm",
            prompt: "How should hard and easy days feel?",
            placeholder: "Ex: one hard interval day, long easy weekend session...",
            suggestions: [
                (title: "One hard day", text: "Use one hard cardio day per week."),
                (title: "Mostly easy", text: "Keep most cardio easy and sustainable."),
                (title: "Long weekend", text: "Put the longest conditioning session on the weekend."),
                (title: "Short weekdays", text: "Keep weekday cardio short."),
                (title: "Recover well", text: "Leave enough recovery between harder sessions.")
            ]
        )
    }

    private var sportSupportQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Sport support",
            prompt: primaryFocusForPersonalization == .climbing
                ? "What should this plan support for climbing?"
                : "What should this plan support for your sport?",
            placeholder: "Ex: climb Tue/Thu, protect grip, stronger legs...",
            suggestions: sportSupportSuggestions
        )
    }

    private var sportPerformanceQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Performance priority",
            prompt: "What should stay fresh or improve for performance?",
            placeholder: "Ex: grip, legs, power, mobility, endurance...",
            suggestions: [
                (title: "Fresh grip", text: "Keep grip and pulling volume fresh for performance days."),
                (title: "Fresh legs", text: "Keep legs fresh for sport days."),
                (title: "More power", text: "Build more power and explosiveness."),
                (title: "More endurance", text: "Build sport-specific endurance."),
                (title: "Mobility support", text: "Use mobility work that helps my sport positions.")
            ]
        )
    }

    private var mobilityTargetQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Mobility target",
            prompt: "What movement or body area should improve most?",
            placeholder: "Ex: hips, shoulders, back, ankles, posture...",
            suggestions: [
                (title: "Hips", text: "Improve hip mobility and control."),
                (title: "Shoulders", text: "Improve shoulder mobility and comfort."),
                (title: "Back", text: "Help my back feel and move better."),
                (title: "Ankles", text: "Improve ankle mobility."),
                (title: "Posture", text: "Improve posture and daily movement quality.")
            ]
        )
    }

    private var mobilityIntegrationQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Mobility style",
            prompt: "Should mobility be its own session or built into workouts?",
            placeholder: "Ex: short daily work, dedicated recovery day, warmups...",
            suggestions: [
                (title: "Built in", text: "Build mobility into warmups and cooldowns."),
                (title: "Dedicated day", text: "Include a dedicated mobility or recovery day."),
                (title: "Short daily", text: "Use short mobility work I can do often."),
                (title: "Recovery-first", text: "Make this recovery-focused and gentle."),
                (title: "Strength support", text: "Use mobility that supports lifting and training.")
            ]
        )
    }

    private var conditioningStyleQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Conditioning style",
            prompt: "What kind of conditioning should this feel like?",
            placeholder: "Ex: athletic circuits, short intervals, low impact...",
            suggestions: [
                (title: "Athletic", text: "Make conditioning feel athletic and performance-focused."),
                (title: "Short intervals", text: "Use short, hard interval sessions."),
                (title: "Low impact", text: "Keep conditioning low impact."),
                (title: "Strength circuits", text: "Use strength-based circuits."),
                (title: "Calorie burn", text: "Bias conditioning toward calorie burn.")
            ]
        )
    }

    private var conditioningIntensityQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Conditioning intensity",
            prompt: "How intense should these sessions be week to week?",
            placeholder: "Ex: one very hard day, moderate, not crushing...",
            suggestions: [
                (title: "One hard day", text: "Use one very hard conditioning day per week."),
                (title: "Moderate", text: "Keep intensity moderate and repeatable."),
                (title: "Not crushing", text: "Avoid sessions that crush recovery."),
                (title: "Progressive", text: "Progress conditioning gradually week to week."),
                (title: "Short weekdays", text: "Keep hard conditioning short on weekdays.")
            ]
        )
    }

    private var focusOutcomeQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Training outcome",
            prompt: "What should this plan help you noticeably improve?",
            placeholder: "Ex: first pull-up, bigger legs, 10K, V5...",
            suggestions: trainingOutcomeSuggestions
        )
    }

    private var focusDetailsQuestion: ProPersonalizationQuestion {
        ProPersonalizationQuestion(
            label: "Workout details",
            prompt: "What should I prioritize or avoid inside the workouts?",
            placeholder: workoutDetailsPlaceholder,
            suggestions: workoutDetailSuggestions
        )
    }

    private var focusBalanceSuggestions: [(title: String, text: String)] {
        var suggestions: [(title: String, text: String)] = []
        if draft.focuses.contains(.strength) {
            suggestions.append((title: "Strength leads", text: "Make strength the main driver and fit the other work around it."))
        }
        if draft.focuses.contains(.cardio) {
            suggestions.append((title: "Cardio leads", text: "Make cardio the main driver and use other sessions to support it."))
        }
        if draft.focuses.contains(.climbing) || draft.focuses.contains(.sport) {
            suggestions.append((title: "Performance leads", text: "Make sport performance the main driver and protect those days."))
        }
        if draft.focuses.contains(.mobility) {
            suggestions.append((title: "Recovery-first", text: "Keep the week recovery-conscious and mobility-forward."))
        }
        if draft.focuses.contains(.hiit) {
            suggestions.append((title: "Conditioning leads", text: "Make conditioning the main driver without crushing recovery."))
        }
        suggestions.append(contentsOf: [
            (title: "Balanced week", text: "Balance the selected focuses evenly across the week."),
            (title: "Short weekdays", text: "Keep weekday sessions shorter and place harder work where it fits.")
        ])
        return Array(suggestions.prefix(6))
    }

    private var sportSupportSuggestions: [(title: String, text: String)] {
        if primaryFocusForPersonalization == .climbing || draft.focuses.contains(.climbing) {
            return [
                (title: "Climb Tue/Thu", text: "Build around climbing on Tuesday and Thursday."),
                (title: "Fresh grip", text: "Keep grip and pulling volume fresh for climbing."),
                (title: "Stronger fingers", text: "Support finger and pulling strength carefully."),
                (title: "Better mobility", text: "Improve mobility for climbing positions."),
                (title: "Strength support", text: "Use strength sessions to support climbing performance.")
            ]
        }
        return [
            (title: "Protect game days", text: "Keep the plan fresh around game or practice days."),
            (title: "More power", text: "Build more power for my sport."),
            (title: "More speed", text: "Build more speed and conditioning."),
            (title: "Injury resilience", text: "Build strength and mobility that keeps me resilient."),
            (title: "Strength support", text: "Use strength sessions to support sport performance.")
        ]
    }

    private var trainingOutcomeSuggestions: [(title: String, text: String)] {
        var suggestions: [(title: String, text: String)] = []
        let cardioIsSupportOnly = isCardioSupportOnlyForPersonalization
        let strengthLeads = isStrengthLeadingForPersonalization

        if draft.focuses.contains(.strength) || draft.goalPresets.contains(.buildMuscle) || draft.goalPresets.contains(.getStronger) {
            suggestions.append(contentsOf: [
                (title: "Main lifts", text: "I want my main strength numbers to move up."),
                (title: "Bigger legs", text: "I want noticeably bigger legs."),
                (title: "Upper body", text: "I want a stronger, more muscular upper body."),
                (title: "First pull-up", text: "I want to work toward my first strict pull-up."),
                (title: "Bench milestone", text: "I want to build toward a stronger bench press.")
            ])
        }
        if cardioIsSupportOnly {
            suggestions.append(contentsOf: [
                (title: "Short support", text: "Keep cardio to one short easy support block after a lift each week."),
                (title: "Recover better", text: "Use cardio only if it helps recovery and conditioning without taking over."),
                (title: "No cardio day", text: "Do not create a dedicated cardio day for this plan.")
            ])
        } else if draft.focuses.contains(.cardio) || draft.goalPresets.contains(.improveEndurance) {
            suggestions.append(contentsOf: [
                (title: "Run farther", text: "I want to build distance without burning out."),
                (title: "Faster pace", text: "I want to improve pace and speed."),
                (title: "Better conditioning", text: "I want better all-around conditioning.")
            ])
        }
        if draft.focuses.contains(.climbing) || draft.focuses.contains(.sport) {
            suggestions.append(contentsOf: [
                (title: "Sport performance", text: "I want this to carry over to my sport."),
                (title: "Climb harder", text: "I want more climbing strength and endurance."),
                (title: "Stay fresh", text: "I want training to support performance without making me feel flat.")
            ])
        }
        if draft.focuses.contains(.mobility) || draft.goalPresets.contains(.moveBetter) {
            suggestions.append(contentsOf: [
                (title: "Move better", text: "I want to move better and feel less restricted."),
                (title: "Less stiffness", text: "I want less stiffness day to day.")
            ])
        }
        if draft.focuses.contains(.hiit) {
            suggestions.append(contentsOf: [
                (title: "More stamina", text: "I want more stamina during hard efforts."),
                (title: "Athletic engine", text: "I want a better athletic engine.")
            ])
        }
        if strengthLeads {
            suggestions.append((title: "Strength first", text: "Make the plan clearly strength-first and keep the other work supportive."))
        }
        suggestions.append((title: "Consistency", text: "I want a plan I can follow consistently."))
        if !cardioIsSupportOnly {
            suggestions.append((title: "Body comp", text: "I want training that supports my body composition goals."))
        }
        var seenTitles = Set<String>()
        let uniqueSuggestions = suggestions.filter { suggestion in
            seenTitles.insert(suggestion.title).inserted
        }
        return Array(uniqueSuggestions.prefix(6))
    }

    private var workoutDetailsPlaceholder: String {
        switch primaryFocusForPersonalization {
        case .cardio:
            return "Ex: low impact, treadmill OK, avoid hills..."
        case .climbing, .sport:
            return "Ex: protect grip, fresh legs, avoid shoulder flare-ups..."
        case .mobility:
            return "Ex: hips tight, avoid deep knee flexion..."
        case .hiit:
            return "Ex: no jumping, kettlebells OK, short sessions..."
        case .strength:
            return "Ex: love cables, no barbell squats, weak hamstrings..."
        case nil:
            return "Ex: short weekdays, avoid jumping, focus legs..."
        }
    }

    private var workoutDetailSuggestions: [(title: String, text: String)] {
        switch primaryFocusForPersonalization {
        case .cardio:
            return [
                (title: "Low impact", text: "Keep cardio low impact."),
                (title: "Treadmill OK", text: "Treadmill work is okay."),
                (title: "Avoid hills", text: "Avoid too much hill work."),
                (title: "Outdoor runs", text: "I prefer outdoor runs when possible."),
                (title: "Protect knees", text: "Be careful with knee stress.")
            ]
        case .climbing, .sport:
            return [
                (title: "Protect grip", text: "Protect grip and pulling recovery."),
                (title: "Fresh legs", text: "Keep legs fresh for performance days."),
                (title: "Shoulders careful", text: "Be careful with shoulder-intensive work."),
                (title: "Mobility support", text: "Include mobility that supports my sport."),
                (title: "Power work", text: "Include power work where it fits.")
            ]
        case .mobility:
            return [
                (title: "Hips tight", text: "Pay extra attention to tight hips."),
                (title: "Shoulders", text: "Pay extra attention to shoulders."),
                (title: "Gentle", text: "Keep mobility work gentle and repeatable."),
                (title: "Warmups", text: "Build mobility into warmups."),
                (title: "Recovery day", text: "Include a recovery-focused session.")
            ]
        case .hiit:
            return [
                (title: "No jumping", text: "Avoid high-impact jumping."),
                (title: "Kettlebells OK", text: "Kettlebells are okay."),
                (title: "Short sessions", text: "Keep HIIT sessions short."),
                (title: "Not too much legs", text: "Do not overload legs with conditioning."),
                (title: "Machines OK", text: "Bike, rower, and machines are okay.")
            ]
        case .strength, nil:
            return [
                (title: "Avoid squats", text: "Avoid heavy barbell squats."),
                (title: "Machines OK", text: "I like using machines and cables."),
                (title: "Free weights", text: "I prefer free weights when possible."),
                (title: "Weak hamstrings", text: "Pay extra attention to hamstrings."),
                (title: "Shoulders careful", text: "Be careful with shoulder-intensive work."),
                (title: "Variety", text: "Keep the workouts varied enough that I do not get bored.")
            ]
        }
    }

    private var selectedProAnswersRow: some View {
        FlowLayout(spacing: 8) {
            if let generationPriority = draft.generationPriority {
                selectedProAnswerChip(
                    title: generationPriority.title,
                    icon: generationPriority.icon
                ) {
                    draft.generationPriority = nil
                    draft.generationStyle = nil
                }
            }
            if let generationStyle = draft.generationStyle {
                selectedProAnswerChip(
                    title: generationStyle.title,
                    icon: generationStyle.icon
                ) {
                    draft.generationStyle = nil
                }
            }
        }
    }

    private var proTuningReviewSummary: some View {
        setupSection(title: "Built around") {
            FlowLayout(spacing: 8) {
                setupSummaryChip(icon: "figure.strengthtraining.traditional", text: selectedFocusText)
                if !selectedGoalText.isEmpty {
                    setupSummaryChip(icon: "flag.checkered", text: "Goals")
                }
                setupSummaryChip(icon: "calendar", text: draft.schedule.title)
                setupSummaryChip(icon: "clock", text: draft.duration.title)
                setupSummaryChip(icon: draft.equipment.iconName, text: draft.equipment.displayName)
                if let generationPriority = draft.generationPriority {
                    setupSummaryChip(icon: generationPriority.icon, text: generationPriority.title)
                }
                if let generationStyle = draft.generationStyle {
                    setupSummaryChip(icon: generationStyle.icon, text: generationStyle.title)
                }
            }
        }
    }

    private var rhythmNotesSection: some View {
        customInstructionsField(
            title: "Schedule notes",
            placeholder: "Best training days, recovery needs, time limits...",
            text: $draft.rhythmNotes
        )
    }

    private var setupNotesSection: some View {
        customInstructionsField(
            title: "Setup notes",
            placeholder: "Equipment you love or avoid, gym limitations, experience details...",
            text: $draft.setupNotes,
            minHeight: 70
        )
    }

    private func customInstructionsField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 86
    ) -> some View {
        setupSection(title: title) {
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: minHeight)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func traiQuestionCard(eyebrow: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TraiLensView(size: 28, state: .answering, breathes: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .onboardingTraiResponseCard(cornerRadius: 18)
    }

    private func proAnswerChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingChip(
            title: title,
            icon: icon,
            isSelected: isSelected
        ) {
            HapticManager.lightTap()
            action()
        }
    }

    private func sendProBrief(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let question = currentProPersonalizationQuestion else { return }
        HapticManager.lightTap()
        let labeledAnswer = "\(question.label): \(trimmed)"
        if draft.trimmedProCoachingNotes.isEmpty {
            draft.proCoachingNotes = labeledAnswer
        } else {
            draft.proCoachingNotes = "\(draft.trimmedProCoachingNotes)\n\(labeledAnswer)"
        }
        proBriefInput = ""
        isProBriefInputFocused = false

        let answerCount = draft.proPersonalizationAnswerCount
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            handleProPersonalizationProgress(afterAnswerCount: answerCount)
        }
    }

    private func handleProPersonalizationProgress(afterAnswerCount answerCount: Int) {
        if shouldGenerateDynamicProPersonalizationQuestion(afterAnswerCount: answerCount) {
            generateDynamicProPersonalizationQuestionIfNeeded()
            return
        }

        proPersonalizationQuestionIndex = min(
            answerCount,
            max(proPersonalizationQuestions.count - 1, 0)
        )
        scheduleProPlanGenerationIfReady()
    }

    private func prepareProPersonalizationIfNeeded() {
        if shouldGenerateDynamicProPersonalizationQuestion(afterAnswerCount: draft.proPersonalizationAnswerCount) {
            generateDynamicProPersonalizationQuestionIfNeeded()
            return
        }
        scheduleProPlanGenerationIfReady()
    }

    private func shouldGenerateDynamicProPersonalizationQuestion(afterAnswerCount answerCount: Int) -> Bool {
        answerCount >= proPersonalizationQuestions.count &&
            answerCount < proPersonalizationTargetQuestionCount &&
            dynamicProPersonalizationQuestions.count < maxDynamicProPersonalizationQuestionCount
    }

    private func generateDynamicProPersonalizationQuestionIfNeeded() {
        guard !isGeneratingProPersonalizationQuestion,
              shouldGenerateDynamicProPersonalizationQuestion(afterAnswerCount: draft.proPersonalizationAnswerCount) else {
            return
        }

        isGeneratingProPersonalizationQuestion = true
        isProBriefInputFocused = false

        let request = draft.buildRequest(context: context)
        let answeredQuestions = proPersonalizationBriefLines

        Task { @MainActor in
            let resolvedQuestion: ProPersonalizationQuestion
            do {
                let followUp = try await aiService.generateWorkoutPlanFollowUpQuestion(
                    request: request,
                    answeredQuestions: answeredQuestions
                )
                resolvedQuestion = ProPersonalizationQuestion(
                    label: "Trai follow-up \(dynamicProPersonalizationQuestions.count + 1)",
                    prompt: followUp.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? focusDetailsQuestion.prompt
                        : followUp.prompt,
                    placeholder: followUp.placeholder?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? followUp.placeholder!
                        : focusDetailsQuestion.placeholder,
                    suggestions: normalizedDynamicSuggestions(followUp.suggestions)
                )
            } catch {
                resolvedQuestion = fallbackDynamicProPersonalizationQuestion
            }

            dynamicProPersonalizationQuestions.append(resolvedQuestion)
            isGeneratingProPersonalizationQuestion = false
            proPersonalizationQuestionIndex = min(
                draft.proPersonalizationAnswerCount,
                max(proPersonalizationQuestions.count - 1, 0)
            )
        }
    }

    private var fallbackDynamicProPersonalizationQuestion: ProPersonalizationQuestion {
        if !proPersonalizationQuestions.contains(where: { $0.label == focusOutcomeQuestion.label }) {
            return focusOutcomeQuestion
        }
        return focusDetailsQuestion
    }

    private func normalizedDynamicSuggestions(
        _ suggestions: [AIService.WorkoutPlanFollowUpSuggestion]
    ) -> [(title: String, text: String)] {
        let cleaned = suggestions.compactMap { suggestion -> (title: String, text: String)? in
            let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !text.isEmpty else { return nil }
            return (title, text)
        }
        if cleaned.isEmpty {
            return focusDetailsQuestion.suggestions
        }
        return Array(cleaned.prefix(5))
    }

    private var proPersonalizationBriefLines: [String] {
        draft.trimmedProCoachingNotes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func scheduleProPlanGenerationIfReady() {
        guard hasAnsweredAllProPersonalizationQuestions,
              !hasQueuedProPlanGeneration,
              generationNote == nil,
              !isGenerating,
              generatedPlanForReview == nil else {
            return
        }

        hasQueuedProPlanGeneration = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard hasAnsweredAllProPersonalizationQuestions,
                  !isGenerating,
                  generatedPlanForReview == nil else {
                hasQueuedProPlanGeneration = false
                return
            }
            generatePlan()
        }
    }

    private func selectedProAnswerChip(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.lightTap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let generatedPlanForReview {
            generatedPlanReviewSection(generatedPlanForReview)
        } else {
            VStack(spacing: 12) {
                setupSection(title: "Ready to create this plan") {
                    VStack(spacing: 10) {
                        reviewRow(icon: "figure.strengthtraining.traditional", title: "Focus", value: selectedFocusText)
                        if !selectedGoalText.isEmpty {
                            reviewRow(icon: "flag.checkered", title: "Goals", value: selectedGoalText)
                        }
                        reviewRow(icon: "calendar", title: "Schedule", value: "\(draft.schedule.title), \(draft.duration.title) sessions")
                        reviewRow(icon: draft.equipment.iconName, title: "Equipment", value: draft.equipment.displayName)
                        reviewRow(icon: draft.experience.iconName, title: "Background", value: draft.experience.displayName)
                        if mode == .manual {
                            reviewRow(icon: draft.preferredSplit.iconName, title: "Plan structure", value: draft.preferredSplit.displayName)
                        }

                        if !selectedConstraintsText.isEmpty {
                            reviewRow(icon: "slider.horizontal.3", title: "Preferences", value: selectedConstraintsText)
                        }

                        if !trimmedRhythmNotes.isEmpty {
                            reviewRow(icon: "calendar.badge.clock", title: "Schedule notes", value: trimmedRhythmNotes)
                        }

                        if !trimmedGoalNotes.isEmpty {
                            reviewRow(icon: "flag.checkered", title: "Goal notes", value: trimmedGoalNotes)
                        }

                        if !trimmedSetupNotes.isEmpty {
                            reviewRow(icon: "dumbbell.fill", title: "Setup notes", value: trimmedSetupNotes)
                        }

                        if !trimmedPreferenceNotes.isEmpty {
                            reviewRow(icon: "text.alignleft", title: "Plan notes", value: trimmedPreferenceNotes)
                        }

                        if !trimmedNotes.isEmpty {
                            reviewRow(icon: "text.alignleft", title: "Notes", value: trimmedNotes)
                        }

                        if mode == .manual {
                            manualReviewProUpsellCard
                                .padding(.top, 2)
                        }
                    }
                }

            }
        }
    }

    private func generatedPlanReviewSection(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if generatedPlanUsedFallback {
                fallbackPlanNotice
            }

            let goals = generatedPlanGoalsForReview

            WorkoutPlanProposalCard(
                plan: plan,
                message: generatedPlanIntroMessage(for: plan),
                onAccept: { saveGeneratedPlan(plan) },
                acceptTitle: "Save Plan",
                onCustomize: nil
            )

            if !goals.isEmpty {
                generatedGoalStrip(goals)
            }
        }
    }

    private var fallbackPlanNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            Text("AI unavailable. Drafted from setup.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onboardingTraiResponseCard(cornerRadius: 14)
    }

    private func generatedPlanIntroMessage(for plan: WorkoutPlan) -> String {
        let focus = plan.planIntent?.primaryFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusText = focus?.isEmpty == false
            ? focus!.trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
            : plan.splitType.displayName.lowercased()
        return "I built a \(plan.daysPerWeek)-day plan around \(focusText). Open the details if you want to review each session, or tell me what to change before you save it."
    }

    private var shortPlanPersonalizationText: String {
        let text = draft.trimmedProCoachingNotes
        guard text.count > 72 else { return text }
        let index = text.index(text.startIndex, offsetBy: 72)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var generatedPlanSuggestionChips: [String] {
        [
            "Shorter sessions",
            "More recovery",
            "Swap exercises",
            "Add cardio"
        ]
    }

    private func generatedPlanSignalStrip(plan: WorkoutPlan, goals: [WorkoutGoal]) -> some View {
        let chips = generatedPlanSignalChips(plan: plan, goals: goals)

        return FlowLayout(spacing: 8) {
            ForEach(chips, id: \.title) { chip in
                generatedSignalChip(chip)
            }
        }
    }

    private func generatedPlanSignalChips(plan: WorkoutPlan, goals: [WorkoutGoal]) -> [GeneratedPlanSignalChip] {
        var chips: [GeneratedPlanSignalChip] = [
            GeneratedPlanSignalChip(icon: "target", title: primaryGeneratedFocusText)
        ]

        if let generationPriority = draft.generationPriority {
            chips.append(GeneratedPlanSignalChip(icon: generationPriority.icon, title: generationPriority.title))
        }
        if let generationStyle = draft.generationStyle {
            chips.append(GeneratedPlanSignalChip(icon: generationStyle.icon, title: generationStyle.title))
        }

        chips.append(GeneratedPlanSignalChip(icon: "calendar", title: "\(plan.daysPerWeek)d/week"))

        if !goals.isEmpty || !selectedGoalText.isEmpty {
            chips.append(GeneratedPlanSignalChip(icon: "flag.checkered", title: "Goals"))
        }
        if !context.nutritionContext.isEmpty {
            chips.append(GeneratedPlanSignalChip(icon: "fork.knife", title: "Nutrition"))
        }
        if !context.memoryContext.isEmpty || !trimmedNotes.isEmpty || !trimmedPreferenceNotes.isEmpty {
            chips.append(GeneratedPlanSignalChip(icon: "sparkles", title: "Notes"))
        }

        return Array(chips.prefix(5))
    }

    private var primaryGeneratedFocusText: String {
        if let firstFocus = draft.focuses.sorted(by: { $0.rawValue < $1.rawValue }).first?.title {
            return firstFocus
        }
        let customFocus = draft.customFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return customFocus.isEmpty ? "Custom" : customFocus
    }

    private func generatedSignalChip(_ chip: GeneratedPlanSignalChip) -> some View {
        HStack(spacing: 6) {
            Image(systemName: chip.icon)
                .font(.caption2.weight(.bold))
            Text(chip.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .capsule)
    }

    private func generatedGoalStrip(_ goals: [WorkoutGoal]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(goals.prefix(2)), id: \.id) { goal in
                Button {
                    openGeneratedPlanChat(prompt: "Adjust this goal: \(goal.trimmedTitle)")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: goal.goalKind.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.trimmedTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text(generatedGoalDetailText(goal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .onboardingTraiResponseCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func generatedGoalDetailText(_ goal: WorkoutGoal) -> String {
        let trackingSummary = goal.trackingSummary
        let supportingSummary = goal.supportingSummary
        let text = [
            trackingSummary,
            goal.scopeSummary,
            supportingSummary == trackingSummary ? nil : supportingSummary,
            goal.horizonSummary
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
        return text.isEmpty ? "Trai will follow up as you train" : text
    }

    private func deduplicatedGoals(_ goals: [WorkoutGoal]) -> [WorkoutGoal] {
        var seen: Set<String> = []
        return goals.filter { goal in
            let key = goal.planSetupDeduplicationKey
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    private func openGeneratedPlanChat(prompt: String?) {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            generatedPlanChatPrompt = trimmed
            generatedPlanRefinementText = ""
        } else {
            generatedPlanChatPrompt = nil
        }
        showingGeneratedPlanChat = true
        HapticManager.lightTap()
    }

    private func saveGeneratedPlan(_ plan: WorkoutPlan) {
        HapticManager.success()
        onComplete(plan, generatedPlanGoalsForReview)
    }

    private func generatedGoalRow(_ goal: WorkoutGoal) -> some View {
        HStack(spacing: 10) {
            Image(systemName: goal.goalKind.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.trimmedTitle)
                    .font(.subheadline.weight(.semibold))
                if let supportingSummary = goal.supportingSummary {
                    Text(supportingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .onboardingTintedGlass(
            tint: TraiColors.brandAccent,
            isSelected: false,
            cornerRadius: 14,
            isInteractive: false
        )
    }

    private func planMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.traiBold(28))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewGeneratedTemplateRow(_ template: WorkoutPlan.WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: template.sessionType.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                Text([template.sessionType.displayName, template.focusAreasDisplay, "\(template.estimatedDurationMinutes) min"]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .onboardingTintedGlass(
            tint: TraiColors.brandAccent,
            isSelected: false,
            cornerRadius: 14,
            isInteractive: false
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isProTuningChatStep {
            proTuningComposerBar
        } else {
            VStack(spacing: 10) {
                if let generationNote {
                    Text(generationNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if generatedPlanForReview != nil, usesAI, !isGenerating {
                    generatedPlanRefinementInput
                } else {
                    Button {
                        advanceOrGenerate()
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: primaryActionIcon)
                            }
                            Text(primaryActionTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.traiPrimary(color: canAdvance && !isGenerating ? .accentColor : .gray, size: .large, fullWidth: true))
                    .accessibilityIdentifier("workoutPlanSetupPrimaryButton")
                    .disabled(!canAdvance || isGenerating)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var proTuningComposerBar: some View {
        VStack(spacing: 0) {
            if shouldShowProGenerationError {
                proGenerationErrorControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !shouldHideProTuningComposer, !proPersonalizationSuggestions.isEmpty {
                proPersonalizationSuggestionRow
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !shouldShowProGenerationError, !shouldHideProTuningComposer {
                SimpleChatInputBar(
                    text: $proBriefInput,
                    placeholder: personalizationPlaceholder,
                    isLoading: false,
                    onSend: { sendProBrief(proBriefInput) },
                    isFocused: $isProBriefInputFocused
                )
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0),
                    Color(.systemBackground).opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeInOut(duration: 0.18), value: draft.trimmedProCoachingNotes)
    }

    private var shouldShowProGenerationError: Bool {
        generationNote != nil &&
            hasAnsweredAllProPersonalizationQuestions &&
            generatedPlanForReview == nil &&
            !isGenerating
    }

    private var proGenerationErrorControls: some View {
        VStack(spacing: 10) {
            if let generationNote {
                Text(generationNote)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                generatePlan()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiPrimary(color: .accentColor, size: .large, fullWidth: true))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var shouldHideProTuningComposer: Bool {
        isGeneratingProPersonalizationQuestion ||
            hasAnsweredAllProPersonalizationQuestions ||
            shouldGenerateDynamicProPersonalizationQuestion(afterAnswerCount: draft.proPersonalizationAnswerCount) ||
            isGenerating ||
            currentProPersonalizationQuestion == nil
    }

    private var proPersonalizationSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(proPersonalizationSuggestions, id: \.title) { suggestion in
                    TraiSelectableChip(text: suggestion.title, isSelected: false) {
                        HapticManager.lightTap()
                        sendProBrief(suggestion.text)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
    }

    private var generatedPlanRefinementInput: some View {
        VStack(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(Array(generatedPlanSuggestionChips.prefix(2)), id: \.self) { suggestion in
                    TraiSelectableChip(text: suggestion, isSelected: false) {
                        openGeneratedPlanChat(prompt: suggestion)
                    }
                }
            }

            SimpleChatInputBar(
                text: $generatedPlanRefinementText,
                placeholder: "Ask Trai to adjust anything...",
                isLoading: false,
                onSend: { openGeneratedPlanChat(prompt: generatedPlanRefinementText) },
                isFocused: $isGeneratedPlanInputFocused
            )
        }
    }

    private var primaryActionTitle: String {
        if generatedPlanForReview != nil {
            return "Save Plan"
        }
        if isGenerating {
            return usesAI ? "Building Plan..." : "Saving Plan..."
        }
        guard isLastStep else { return "Continue" }
        return usesAI ? "Build with Trai Pro" : "Save Plan"
    }

    private var primaryActionIcon: String {
        if generatedPlanForReview != nil {
            return "checkmark.circle.fill"
        }
        if isLastStep {
            return usesAI ? "circle.hexagongrid.circle.fill" : "checkmark.circle.fill"
        }
        return "arrow.right"
    }

    private var generatingPage: some View {
        generationContextChips
        .padding(.top, 10)
        .onAppear {
            if generationStartedAt == nil {
                generationStartedAt = Date()
            }
            generationStatusTitle = "Creating your plan"
        }
    }

    private var generationContextChips: some View {
        FlowLayout(spacing: 8) {
            if let focus = draft.focuses.sorted(by: { $0.rawValue < $1.rawValue }).first {
                let extraCount = max(draft.focuses.count - 1, 0)
                setupSummaryChip(
                    icon: focus.icon,
                    text: extraCount > 0 ? "\(focus.title) +\(extraCount)" : focus.title
                )
            }
            setupSummaryChip(icon: "calendar", text: draft.schedule.title)
            setupSummaryChip(icon: "clock", text: draft.duration.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isLastStep: Bool {
        currentStep == steps.last
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .focus:
            return draft.canGenerate
        case .tuning:
            return hasAnsweredAllProPersonalizationQuestions
        default:
            return true
        }
    }

    private var selectedFocusText: String {
        var values = draft.focuses
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
        let customFocus = draft.customFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customFocus.isEmpty {
            values.append(customFocus)
        }
        return values.joined(separator: ", ")
    }

    private var selectedConstraintsText: String {
        draft.constraints
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    private var selectedGoalText: String {
        draft.goalPresets
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    private var trimmedNotes: String {
        draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRhythmNotes: String {
        draft.rhythmNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedGoalNotes: String {
        draft.goalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSetupNotes: String {
        draft.setupNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPreferenceNotes: String {
        draft.preferenceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func equipmentTint(for equipment: WorkoutPlanGenerationRequest.EquipmentAccess) -> Color {
        switch equipment {
        case .fullGym:
            TraiColors.flame
        case .homeAdvanced:
            TraiColors.coral
        case .homeBasic:
            Color.accentColor
        case .bodyweightOnly:
            TraiColors.blaze
        }
    }

    private var weeklyRhythmControl: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                rhythmAdjustButton(systemName: "minus") {
                    adjustScheduleDays(by: -1)
                }
                .disabled(draft.schedule.days == nil || concreteScheduleDays <= 2)

                VStack(spacing: 4) {
                    Text(draft.schedule.days.map { "\($0)" } ?? "Flex")
                        .font(.traiBold(34))
                        .monospacedDigit()

                    Text(draft.schedule.days == nil ? "flexible schedule" : "days per week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                rhythmAdjustButton(systemName: "plus") {
                    adjustScheduleDays(by: 1)
                }
                .disabled(draft.schedule.days == nil || concreteScheduleDays >= 5)
            }
            .padding(14)
            .onboardingTraiResponseCard(cornerRadius: 18)

            if usesAI {
                OnboardingChip(
                    title: "Let Trai choose the weekly rhythm",
                    icon: "sparkles",
                    isSelected: draft.schedule == .flexible
                ) {
                    HapticManager.lightTap()
                    draft.schedule = draft.schedule == .flexible ? .threeDays : .flexible
                }
            }
        }
    }

    private var concreteScheduleDays: Int {
        draft.schedule.days ?? 3
    }

    private func rhythmAdjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.10)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func adjustScheduleDays(by delta: Int) {
        HapticManager.lightTap()
        if draft.schedule == .flexible {
            draft.schedule = .threeDays
            return
        }
        setScheduleDays(min(max(concreteScheduleDays + delta, 2), 5))
    }

    private var sessionLengthControl: some View {
        HStack(spacing: 14) {
            rhythmAdjustButton(systemName: "minus") {
                adjustSessionLength(by: -1)
            }
            .disabled(durationIndex <= 0)

            VStack(spacing: 4) {
                Text("\(draft.duration.rawValue)")
                    .font(.traiBold(34))
                    .monospacedDigit()

                Text("minutes per session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            rhythmAdjustButton(systemName: "plus") {
                adjustSessionLength(by: 1)
            }
            .disabled(durationIndex >= OnboardingWorkoutDuration.allCases.count - 1)
        }
        .padding(14)
        .onboardingTraiResponseCard(cornerRadius: 18)
    }

    private var durationIndex: Int {
        OnboardingWorkoutDuration.allCases.firstIndex(of: draft.duration) ?? 1
    }

    private func adjustSessionLength(by delta: Int) {
        HapticManager.lightTap()
        let durations = OnboardingWorkoutDuration.allCases
        let nextIndex = min(max(durationIndex + delta, durations.startIndex), durations.index(before: durations.endIndex))
        draft.duration = durations[nextIndex]
    }

    private func setScheduleDays(_ days: Int) {
        switch days {
        case 2:
            draft.schedule = .twoDays
        case 4:
            draft.schedule = .fourDays
        case 5:
            draft.schedule = .fiveDays
        default:
            draft.schedule = .threeDays
        }
    }

    private func experienceTint(for experience: WorkoutPlanGenerationRequest.ExperienceLevel) -> Color {
        switch experience {
        case .beginner:
            TraiColors.coral
        case .intermediate:
            Color.accentColor
        case .advanced:
            TraiColors.flame
        }
    }

    private var manualReviewProUpsellCard: some View {
        ProUpsellInlineCard(
            source: .workoutPlan,
            title: "Let Trai build the full plan",
            message: "Get sessions, exercises, goals, and workout-time coaching from this setup.",
            systemImage: "circle.hexagongrid.circle.fill",
            actionTitle: "Build with Trai Pro",
            showsActionButton: false,
            usesIconContainer: false
        ) {
            HapticManager.lightTap()
            onProForkRequired?()
        }
    }

    private func setupSection<Content: View>(
        title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .onboardingTintedGlass(
            tint: currentStep.accentColor,
            isSelected: false,
            cornerRadius: 14,
            isInteractive: false
        )
    }

    private var summaryStrip: some View {
        HStack(alignment: .top) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    setupSummaryChip(icon: "calendar", text: draft.schedule.title)
                    setupSummaryChip(icon: "clock", text: draft.duration.title)
                    setupSummaryChip(icon: draft.equipment.iconName, text: draft.equipment.displayName)
                }
            }
        }
        .onboardingTraiResponseCard(cornerRadius: 16)
    }

    private func setupSummaryChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }

    private func optionGrid<Value: Identifiable & Hashable>(
        _ values: [Value],
        selection: Binding<Value>,
        minHeight: CGFloat = 88,
        content: @escaping (Value) -> OptionContent
    ) -> some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(values) { value in
                    let option = content(value)
                    OnboardingChoiceCard(
                        title: option.title,
                        hint: nil,
                        iconName: option.icon,
                        tint: option.tint,
                        isSelected: selection.wrappedValue == value,
                        minHeight: minHeight
                    ) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    private func selectableTile(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            (isSelected ? Color.accentColor : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.accent)
                    }
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func selectablePill(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.lightTap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func toggleFocus(_ focus: OnboardingWorkoutFocus) {
        HapticManager.lightTap()
        let hasCustomFocus = !draft.customFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if draft.focuses.contains(focus), draft.focuses.count > 1 || hasCustomFocus {
            draft.focuses.remove(focus)
        } else {
            draft.focuses.insert(focus)
        }
    }

    private func advanceOrGenerate() {
        guard canAdvance, !isGenerating else { return }
        if let generatedPlanForReview {
            HapticManager.success()
            onComplete(generatedPlanForReview, generatedPlanGoalsForReview)
            return
        }
        if isLastStep {
            generatePlan()
        } else {
            goForward()
        }
    }

    private func goForward() {
        let steps = self.steps
        guard let index = steps.firstIndex(of: currentStep), index < steps.index(before: steps.endIndex) else {
            return
        }
        let nextStep = steps[index + 1]
        if mode == .proAI,
           showsProForkBeforeReview,
           !canAccessAIFeatures,
           nextStep == .tuning {
            HapticManager.selectionChanged()
            onProForkRequired?()
            return
        }
        HapticManager.lightTap()
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = nextStep
        }
    }

    private func goBack() {
        let steps = self.steps
        guard let index = steps.firstIndex(of: currentStep), index > steps.startIndex else {
            onBack()
            return
        }
        HapticManager.lightTap()
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = steps[index - 1]
        }
    }

    private func generatePlan() {
        guard draft.canGenerate, !isGenerating else { return }

        isGenerating = true
        generationStartedAt = Date()
        generationStatusTitle = "Creating your plan"
        generationNote = nil
        generatedPlanGoalsForReview = []
        var planDraft = draft
        if !usesAI, planDraft.preferredSplit == .letTraiDecide {
            planDraft.preferredSplit = .fullBody
        }
        let request = planDraft.buildRequest(context: context)

        Task { @MainActor in
            guard usesAI else {
                let plan = planDraft.buildManualPlan(context: context)
                isGenerating = false
                generationStartedAt = nil
                HapticManager.success()
                onComplete(plan, [])
                return
            }

            do {
                generationStatusTitle = "Creating your plan"
                let result = try await aiService.generateWorkoutPlanWithGoalSuggestions(
                    request: request,
                    userGoal: context.goal.displayName,
                    memoryContext: goalGenerationContext(from: request),
                    existingGoals: context.activeWorkoutGoalContext,
                    userIntent: draft.trimmedProCoachingNotes.isEmpty ? request.preferences : draft.trimmedProCoachingNotes,
                    prefersMetricWeight: true
                )
                generatedPlanForReview = result.plan
                generatedPlanGoalsForReview = deduplicatedGoals(
                    result.goalSuggestions
                        .map { $0.asWorkoutGoal() }
                        .filter(\.hasValidTrackingCriteria)
                )
                generatedPlanUsedFallback = false
                isGenerating = false
                generationStartedAt = nil
                HapticManager.success()
            } catch {
                generatedPlanForReview = nil
                generatedPlanGoalsForReview = []
                generatedPlanUsedFallback = true
                hasQueuedProPlanGeneration = false
                let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                generationNote = message.isEmpty
                    ? "Trai could not build your plan. Please try again."
                    : message
                isGenerating = false
                generationStartedAt = nil
                HapticManager.error()
            }
        }
    }

    private func goalGenerationContext(from request: WorkoutPlanGenerationRequest) -> [String] {
        var values: [String] = []
        values.append(contentsOf: request.conversationContext ?? [])
        values.append(contentsOf: context.nutritionContext)
        values.append(contentsOf: context.memoryContext)
        values.append(contentsOf: context.activeWorkoutGoalContext.map { "Existing workout goal: \($0)" })
        return values
    }
}

private extension WorkoutGoal {
    var planSetupDeduplicationKey: String {
        let combinedText = [
            title,
            successCriteria,
            notes,
            linkedActivityName ?? "",
            linkedWorkoutTypeRaw ?? ""
        ]
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .lowercased()

        if combinedText.contains("session"),
           combinedText.contains("week"),
           combinedText.contains("complete") || combinedText.contains("hit") || combinedText.contains("scheduled") {
            return "plan-adherence|\(linkedWorkoutTypeRaw ?? "any")|\(periodUnitRaw ?? "week")|\(periodCount ?? 1)"
        }

        if combinedText.contains("cardio"),
           combinedText.contains("push day") || combinedText.contains("finisher") {
            return "cardio-placement|\(linkedWorkoutTypeRaw ?? "any")|\(periodUnitRaw ?? "week")|\(periodCount ?? 1)"
        }

        if goalKind == .frequency {
            return [
                goalKind.rawValue,
                linkedWorkoutTypeRaw ?? "any",
                linkedActivityName?.goalNormalizedKey ?? "",
                targetValue.map { String(Int($0.rounded())) } ?? "",
                targetUnit.goalNormalizedKey,
                periodUnitRaw ?? "",
                periodCount.map(String.init) ?? ""
            ].joined(separator: "|")
        }

        return title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    var hasValidTrackingCriteria: Bool {
        guard !trimmedSuccessCriteria.isEmpty else { return false }

        switch goalKind {
        case .milestone:
            return true
        case .frequency:
            return targetValue.map { $0 > 0 } == true &&
                periodUnit != nil &&
                !(targetUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .duration, .distance, .weight:
            return targetValue.map { $0 > 0 } == true &&
                !(targetUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct OptionContent {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

private extension WorkoutPlanGenerationRequest.PreferredSplit {
    var splitType: WorkoutPlan.SplitType {
        switch self {
        case .pushPullLegs:
            .pushPullLegs
        case .upperLower:
            .upperLower
        case .fullBody:
            .fullBody
        case .broSplit:
            .bodyPartSplit
        case .letTraiDecide:
            .custom
        }
    }

    var shortDisplayName: String {
        switch self {
        case .pushPullLegs:
            "PPL"
        case .upperLower:
            "Upper/Lower"
        case .fullBody:
            "Full Body"
        case .broSplit:
            "Body Part"
        case .letTraiDecide:
            "Trai Decides"
        }
    }
}

private extension WorkoutPlanGenerationRequest.WorkoutType {
    var workoutMode: WorkoutMode? {
        switch self {
        case .strength:
            .strength
        case .cardio:
            .cardio
        case .hiit:
            .hiit
        case .flexibility:
            .mobility
        case .mixed:
            nil
        }
    }
}

private extension Array where Element: Hashable {
    var uniquedPreservingOrder: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    OnboardingWorkoutPlanSetupView(
        draft: .constant(OnboardingWorkoutPlanDraft()),
        context: OnboardingWorkoutPlanUserContext(
            name: "Nadav",
            age: 30,
            gender: .notSpecified,
            goal: .recomposition,
            activityLevel: .moderate
        ),
        aiService: AIService(),
        onComplete: { _, _ in },
        onBack: {}
    )
}
