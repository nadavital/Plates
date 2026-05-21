//
//  WorkoutPlan.swift
//  Trai
//
//  Represents an AI-generated workout plan with splits and templates
//  This is a Codable struct (not SwiftData) since it's generated dynamically
//

import Foundation

/// Represents a user's workout plan with split structure and exercise templates
struct WorkoutPlan: Codable, Equatable {
    let splitType: SplitType
    let daysPerWeek: Int
    let templates: [WorkoutTemplate]
    let planIntent: PlanIntent?
    let rationale: String
    let guidelines: [String]
    let progressionStrategy: ProgressionStrategy
    let modalityProgression: ModalityProgression?
    let warnings: [String]?

    init(
        splitType: SplitType,
        daysPerWeek: Int,
        templates: [WorkoutTemplate],
        planIntent: PlanIntent? = nil,
        rationale: String,
        guidelines: [String],
        progressionStrategy: ProgressionStrategy,
        modalityProgression: ModalityProgression? = nil,
        warnings: [String]? = nil
    ) {
        self.splitType = splitType
        self.daysPerWeek = daysPerWeek
        self.templates = templates
        self.planIntent = planIntent
        self.rationale = rationale
        self.guidelines = guidelines
        self.progressionStrategy = progressionStrategy
        self.modalityProgression = modalityProgression
        self.warnings = warnings
    }

    // MARK: - Plan Intent

    struct PlanIntent: Codable, Equatable {
        let primaryFocus: String
        let supportingFocuses: [String]
        let sessionAllocation: String
        let honoredInputs: [String]
        let avoided: [String]
        let summary: String

        init(
            primaryFocus: String,
            supportingFocuses: [String] = [],
            sessionAllocation: String,
            honoredInputs: [String] = [],
            avoided: [String] = [],
            summary: String
        ) {
            self.primaryFocus = primaryFocus
            self.supportingFocuses = supportingFocuses
            self.sessionAllocation = sessionAllocation
            self.honoredInputs = honoredInputs
            self.avoided = avoided
            self.summary = summary
        }
    }

    // MARK: - Split Type

    enum SplitType: String, Codable, CaseIterable, Identifiable {
        case pushPullLegs = "pushPullLegs"
        case upperLower = "upperLower"
        case fullBody = "fullBody"
        case bodyPartSplit = "bodyPartSplit"
        case custom = "custom"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pushPullLegs: "Push/Pull/Legs"
            case .upperLower: "Upper/Lower"
            case .fullBody: "Full Body"
            case .bodyPartSplit: "Body Part Split"
            case .custom: "Custom Plan"
            }
        }

        var description: String {
            switch self {
            case .pushPullLegs: "Train push muscles, pull muscles, and legs on separate days"
            case .upperLower: "Alternate between upper and lower body workouts"
            case .fullBody: "Train your entire body each session"
            case .bodyPartSplit: "Dedicate each day to specific muscle groups"
            case .custom: "A personalized training plan based on your preferences"
            }
        }

        var recommendedDaysPerWeek: ClosedRange<Int> {
            switch self {
            case .pushPullLegs: 3...6
            case .upperLower: 3...4
            case .fullBody: 2...4
            case .bodyPartSplit: 4...6
            case .custom: 2...6
            }
        }

        var iconName: String {
            switch self {
            case .pushPullLegs: "arrow.left.arrow.right"
            case .upperLower: "arrow.up.arrow.down"
            case .fullBody: "figure.walk"
            case .bodyPartSplit: "rectangle.split.3x1"
            case .custom: "slider.horizontal.3"
            }
        }
    }

    // MARK: - Workout Template

    struct WorkoutTemplate: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let sessionType: WorkoutMode
        let focusAreas: [String]
        let targetMuscleGroups: [String]
        let exercises: [ExerciseTemplate]
        let blocks: [TrainingBlock]
        let estimatedDurationMinutes: Int
        let order: Int
        let notes: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case sessionType
            case focusAreas
            case targetMuscleGroups
            case exercises
            case blocks
            case estimatedDurationMinutes
            case order
            case notes
        }

        init(
            id: UUID = UUID(),
            name: String,
            sessionType: WorkoutMode = .strength,
            focusAreas: [String]? = nil,
            targetMuscleGroups: [String],
            exercises: [ExerciseTemplate],
            blocks: [TrainingBlock]? = nil,
            estimatedDurationMinutes: Int,
            order: Int,
            notes: String? = nil
        ) {
            self.id = id
            self.name = name
            self.sessionType = sessionType
            self.focusAreas = (focusAreas ?? targetMuscleGroups)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.targetMuscleGroups = targetMuscleGroups
            self.exercises = exercises
            self.blocks = blocks?.normalizedForDisplay ?? Self.defaultBlocks(
                sessionType: sessionType,
                exercises: exercises,
                durationMinutes: estimatedDurationMinutes,
                notes: notes
            )
            self.estimatedDurationMinutes = estimatedDurationMinutes
            self.order = order
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            targetMuscleGroups = try container.decodeIfPresent([String].self, forKey: .targetMuscleGroups) ?? []
            exercises = try container.decodeIfPresent([ExerciseTemplate].self, forKey: .exercises) ?? []
            estimatedDurationMinutes = try container.decode(Int.self, forKey: .estimatedDurationMinutes)
            order = try container.decode(Int.self, forKey: .order)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            id = container.decodeStableUUIDIfPresent(
                forKey: .id,
                namespace: "workout-template",
                fallbackSeed: "\(order)-\(name)"
            )

            let decodedFocusAreas = try container.decodeIfPresent([String].self, forKey: .focusAreas) ?? targetMuscleGroups
            focusAreas = decodedFocusAreas
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            sessionType = try container.decodeIfPresent(WorkoutMode.self, forKey: .sessionType)
                ?? WorkoutMode.infer(from: name, focusAreas: focusAreas, targetMuscleGroups: targetMuscleGroups)
            let decodedBlocks = try container.decodeIfPresent([TrainingBlock].self, forKey: .blocks) ?? []
            blocks = decodedBlocks.normalizedForDisplay
        }

        nonisolated var structuredExercises: [ExerciseTemplate] {
            if !exercises.isEmpty { return exercises }
            return displayBlocks
                .flatMap(\.exercises)
                .sorted { $0.order < $1.order }
        }

        nonisolated var exerciseCount: Int { structuredExercises.count }

        nonisolated var resolvedTargetMuscleGroups: [String] {
            let explicitTargets = targetMuscleGroups
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !explicitTargets.isEmpty {
                return explicitTargets
            }

            var seen: Set<String> = []
            return structuredExercises.compactMap { exercise in
                let value = exercise.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                let key = value.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return value
            }
        }

        nonisolated var displayBlocks: [TrainingBlock] {
            blocks.isEmpty
                ? Self.defaultBlocks(
                    sessionType: sessionType,
                    exercises: exercises,
                    durationMinutes: estimatedDurationMinutes,
                    notes: notes
                )
                : blocks.normalizedForDisplay
        }

        nonisolated var primaryBlockSummary: String {
            displayBlocks
                .prefix(3)
                .map(\.shortSummary)
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
        }

        nonisolated var muscleGroupsDisplay: String {
            (focusAreas.isEmpty ? resolvedTargetMuscleGroups : focusAreas)
                .map(Self.formatTargetGroupName)
                .joined(separator: " • ")
        }

        nonisolated var focusAreasDisplay: String {
            muscleGroupsDisplay
        }

        private nonisolated static func formatTargetGroupName(_ raw: String) -> String {
            let normalized = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(
                    of: #"(?<=[a-z])(?=[A-Z])"#,
                    with: " ",
                    options: .regularExpression
                )

            switch normalized.lowercased() {
            case "hiit":
                return "HIIT"
            case "push pull legs":
                return "Push/Pull/Legs"
            default:
                return normalized.localizedCapitalized
            }
        }

        private nonisolated static func defaultBlocks(
            sessionType: WorkoutMode,
            exercises: [ExerciseTemplate],
            durationMinutes: Int,
            notes: String?
        ) -> [TrainingBlock] {
            if !exercises.isEmpty {
                return [
                    TrainingBlock(
                        kind: .strength,
                        title: sessionType == .hiit ? "Work" : "Strength",
                        detail: exercises.prefix(3).map(\.exerciseName).joined(separator: ", "),
                        exercises: exercises,
                        durationMinutes: durationMinutes,
                        intensity: nil,
                        target: nil,
                        order: 0,
                        notes: notes
                    )
                ]
            }

            let title = sessionType.displayName
            return [
                TrainingBlock(
                    kind: TrainingBlock.BlockKind(sessionType: sessionType),
                    title: title,
                    detail: notes ?? "\(durationMinutes) minutes",
                    exercises: [],
                    durationMinutes: durationMinutes,
                    intensity: nil,
                    target: nil,
                    order: 0,
                    notes: notes
                )
            ]
        }
    }

    // MARK: - Training Block

    struct TrainingBlock: Codable, Equatable, Identifiable {
        let id: UUID
        let kind: BlockKind
        let role: Role
        let title: String
        let detail: String
        let exercises: [ExerciseTemplate]
        let durationMinutes: Int?
        let intensity: String?
        let target: String?
        let order: Int
        let notes: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case kind
            case role
            case title
            case detail
            case exercises
            case durationMinutes
            case intensity
            case target
            case order
            case notes
        }

        nonisolated enum BlockKind: String, Codable, CaseIterable, Identifiable {
            case warmup
            case strength
            case cardio
            case conditioning
            case skill
            case mobility
            case recovery
            case sportPractice
            case cooldown
            case custom

            nonisolated var id: String { rawValue }

            nonisolated var displayName: String {
                switch self {
                case .warmup: "Warmup"
                case .strength: "Strength"
                case .cardio: "Cardio"
                case .conditioning: "Conditioning"
                case .skill: "Skill"
                case .mobility: "Mobility"
                case .recovery: "Recovery"
                case .sportPractice: "Practice"
                case .cooldown: "Cooldown"
                case .custom: "Block"
                }
            }

            nonisolated var iconName: String {
                switch self {
                case .warmup: "figure.walk"
                case .strength: "dumbbell.fill"
                case .cardio: "figure.run"
                case .conditioning: "bolt.heart.fill"
                case .skill: "scope"
                case .mobility: "figure.mind.and.body"
                case .recovery: "heart.text.square.fill"
                case .sportPractice: "sportscourt.fill"
                case .cooldown: "figure.cooldown"
                case .custom: "slider.horizontal.3"
                }
            }

            nonisolated init(sessionType: WorkoutMode) {
                switch sessionType {
                case .strength:
                    self = .strength
                case .cardio:
                    self = .cardio
                case .hiit:
                    self = .conditioning
                case .climbing:
                    self = .skill
                case .yoga, .pilates, .flexibility, .mobility:
                    self = .mobility
                case .recovery:
                    self = .recovery
                case .mixed:
                    self = .custom
                case .custom:
                    self = .custom
                }
            }
        }

        nonisolated enum Role: String, Codable, CaseIterable, Identifiable {
            case main
            case warmup
            case accessory
            case finisher
            case cooldown
            case custom

            nonisolated var id: String { rawValue }

            nonisolated var displayName: String {
                switch self {
                case .main: "Main"
                case .warmup: "Warmup"
                case .accessory: "Accessory"
                case .finisher: "Finisher"
                case .cooldown: "Cooldown"
                case .custom: "Custom"
                }
            }

            nonisolated var iconName: String {
                switch self {
                case .main: "target"
                case .warmup: "figure.walk"
                case .accessory: "plus.circle"
                case .finisher: "timer"
                case .cooldown: "figure.cooldown"
                case .custom: "slider.horizontal.3"
                }
            }

            nonisolated static func defaultRole(for kind: BlockKind) -> Role {
                switch kind {
                case .warmup:
                    return .warmup
                case .cooldown:
                    return .cooldown
                case .custom:
                    return .custom
                case .strength, .cardio, .conditioning, .skill, .mobility, .recovery, .sportPractice:
                    return .main
                }
            }

        }

        nonisolated init(
            id: UUID = UUID(),
            kind: BlockKind,
            role: Role? = nil,
            title: String,
            detail: String,
            exercises: [ExerciseTemplate] = [],
            durationMinutes: Int? = nil,
            intensity: String? = nil,
            target: String? = nil,
            order: Int,
            notes: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.role = role ?? Role.defaultRole(for: kind)
            self.title = title
            self.detail = detail
            self.exercises = exercises
            self.durationMinutes = durationMinutes
            self.intensity = intensity
            self.target = target
            self.order = order
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawKind = try container.decode(String.self, forKey: .kind)
            kind = BlockKind(rawValue: rawKind) ?? .custom
            role = try container.decodeIfPresent(Role.self, forKey: .role)
                ?? Role.defaultRole(for: kind)
            title = try container.decode(String.self, forKey: .title)
            detail = try container.decode(String.self, forKey: .detail)
            exercises = try container.decodeIfPresent([ExerciseTemplate].self, forKey: .exercises) ?? []
            durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
            target = try container.decodeIfPresent(String.self, forKey: .target)
            order = try container.decode(Int.self, forKey: .order)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            id = container.decodeStableUUIDIfPresent(
                forKey: .id,
                namespace: "training-block",
                fallbackSeed: "\(order)-\(kind.rawValue)-\(title)"
            )
        }

        nonisolated var shortSummary: String {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let durationMinutes, durationMinutes > 0 {
                return "\(trimmedTitle.isEmpty ? kind.displayName : trimmedTitle) \(durationMinutes)m"
            }
            return trimmedTitle.isEmpty ? kind.displayName : trimmedTitle
        }
    }

    // MARK: - Exercise Template

    struct ExerciseTemplate: Codable, Equatable, Identifiable {
        let id: UUID
        let exerciseName: String
        let muscleGroup: String
        let defaultSets: Int
        let defaultReps: Int
        let repRange: String?
        let restSeconds: Int?
        let notes: String?
        let order: Int

        private enum CodingKeys: String, CodingKey {
            case id
            case exerciseName
            case muscleGroup
            case defaultSets
            case defaultReps
            case repRange
            case restSeconds
            case notes
            case order
        }

        init(
            id: UUID = UUID(),
            exerciseName: String,
            muscleGroup: String,
            defaultSets: Int,
            defaultReps: Int,
            repRange: String? = nil,
            restSeconds: Int? = nil,
            notes: String? = nil,
            order: Int
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.muscleGroup = muscleGroup
            self.defaultSets = defaultSets
            self.defaultReps = defaultReps
            self.repRange = repRange
            self.restSeconds = restSeconds
            self.notes = notes
            self.order = order
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            exerciseName = try container.decode(String.self, forKey: .exerciseName)
            muscleGroup = try container.decode(String.self, forKey: .muscleGroup)
            defaultSets = try container.decode(Int.self, forKey: .defaultSets)
            defaultReps = try container.decode(Int.self, forKey: .defaultReps)
            repRange = try container.decodeIfPresent(String.self, forKey: .repRange)
            restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            order = try container.decode(Int.self, forKey: .order)
            id = container.decodeStableUUIDIfPresent(
                forKey: .id,
                namespace: "exercise-template",
                fallbackSeed: "\(order)-\(exerciseName)"
            )
        }

        var setsRepsDisplay: String {
            if let range = repRange {
                return "\(defaultSets)×\(range)"
            }
            return "\(defaultSets)×\(defaultReps)"
        }
    }

    // MARK: - Progression Strategy

    struct ProgressionStrategy: Codable, Equatable {
        let type: ProgressionType
        let weightIncrementKg: Double
        let repsTrigger: Int?
        let description: String

        enum ProgressionType: String, Codable {
            case linearProgression = "linearProgression"
            case doubleProgression = "doubleProgression"
            case periodized = "periodized"

            var displayName: String {
                switch self {
                case .linearProgression: "Linear Progression"
                case .doubleProgression: "Double Progression"
                case .periodized: "Periodized"
                }
            }
        }

        static let defaultStrategy = ProgressionStrategy(
            type: .doubleProgression,
            weightIncrementKg: 2.5,
            repsTrigger: 12,
            description: "Increase reps until you hit the target, then add weight and reset reps"
        )
    }

    struct ModalityProgression: Codable, Equatable {
        let focus: ProgressionFocus
        let weeklyProgression: String
        let targets: [ProgressionTarget]

        enum ProgressionFocus: String, Codable, CaseIterable {
            case strength
            case volume
            case endurance
            case skill
            case mobility
            case consistency
            case mixed

            var displayName: String {
                switch self {
                case .strength: "Strength"
                case .volume: "Volume"
                case .endurance: "Endurance"
                case .skill: "Skill"
                case .mobility: "Mobility"
                case .consistency: "Consistency"
                case .mixed: "Mixed"
                }
            }
        }

        struct ProgressionTarget: Codable, Equatable, Identifiable {
            let id: UUID
            let label: String
            let metric: String
            let direction: String

            private enum CodingKeys: String, CodingKey {
                case id
                case label
                case metric
                case direction
            }

            init(
                id: UUID = UUID(),
                label: String,
                metric: String,
                direction: String
            ) {
                self.id = id
                self.label = label
                self.metric = metric
                self.direction = direction
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                label = try container.decode(String.self, forKey: .label)
                metric = try container.decode(String.self, forKey: .metric)
                direction = try container.decode(String.self, forKey: .direction)
                id = container.decodeStableUUIDIfPresent(
                    forKey: .id,
                    namespace: "progression-target",
                    fallbackSeed: "\(label)-\(metric)"
                )
            }
        }
    }

    // MARK: - JSON Serialization

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func fromJSON(_ json: String) -> WorkoutPlan? {
        guard let data = json.data(using: .utf8),
              let plan = try? JSONDecoder().decode(WorkoutPlan.self, from: data) else {
            return nil
        }
        return plan
    }

    // MARK: - Placeholder

    static let placeholder = WorkoutPlan(
        splitType: .pushPullLegs,
        daysPerWeek: 3,
        templates: [],
        planIntent: nil,
        rationale: "",
        guidelines: [],
        progressionStrategy: .defaultStrategy,
        modalityProgression: nil,
        warnings: nil
    )
}

private extension Array where Element == WorkoutPlan.TrainingBlock {
    nonisolated var normalizedForDisplay: [WorkoutPlan.TrainingBlock] {
        sorted { $0.order < $1.order }.enumerated().map { index, block in
            WorkoutPlan.TrainingBlock(
                id: block.id,
                kind: block.kind,
                role: block.role,
                title: block.title,
                detail: block.detail,
                exercises: block.exercises,
                durationMinutes: block.durationMinutes,
                intensity: block.intensity,
                target: block.target,
                order: index,
                notes: block.notes
            )
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeStableUUIDIfPresent(
        forKey key: Key,
        namespace: String,
        fallbackSeed: String
    ) -> UUID {
        if let uuid = try? decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }

        if let rawID = try? decodeIfPresent(String.self, forKey: key) {
            let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            if let uuid = UUID(uuidString: trimmedID) {
                return uuid
            }
            if !trimmedID.isEmpty {
                return StableUUID.from("\(namespace):\(trimmedID)")
            }
        }

        return StableUUID.from("\(namespace):\(fallbackSeed)")
    }
}
