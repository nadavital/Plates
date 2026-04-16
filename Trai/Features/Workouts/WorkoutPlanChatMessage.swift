//
//  WorkoutPlanChatMessage.swift
//  Trai
//
//  Message model for the unified workout plan chat flow
//

import Foundation

// MARK: - Chat Message

/// A message in the workout plan conversation
struct WorkoutPlanFlowMessage: Identifiable {
    let id: UUID
    let type: MessageType
    let timestamp: Date

    init(type: MessageType) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
    }

    enum MessageType {
        /// Trai asks a question with suggestion chips
        case question(TraiQuestionConfig)

        /// User's answer (from chips or typed)
        case userAnswer([String])

        /// Trai is thinking/generating
        case thinking(String)

        /// Generated plan proposal with accept/customize options
        case planProposal(WorkoutPlan, String)

        /// Existing saved plan shown as the starting point for editing
        case currentPlan(WorkoutPlan, String)

        /// Plan was accepted
        case planAccepted

        /// Regular chat message from Trai
        case traiMessage(String)

        /// Plan was updated after refinement
        case planUpdated(WorkoutPlan)

        /// Error message
        case error(String)
    }
}

// MARK: - Workout Questions

/// All the questions Trai asks during workout plan creation
enum WorkoutPlanQuestion: String, CaseIterable {
    case workoutType
    case experience
    case equipment
    case schedule
    case cardio      // Conditional: only for cardio/mixed/hiit
    case goals
    case injuries

    var config: TraiQuestionConfig {
        switch self {
        case .workoutType:
            return TraiQuestionConfig(
                id: rawValue,
                question: "What kinds of sessions do you want in this plan?",
                suggestions: [
                    TraiSuggestion("Strength", subtitle: "Lifting and progressive overload"),
                    TraiSuggestion("Cardio", subtitle: "Running, cycling, swimming"),
                    TraiSuggestion("Climbing", subtitle: "Bouldering, rope, technique"),
                    TraiSuggestion("Yoga", subtitle: "Flow, recovery, breathwork"),
                    TraiSuggestion("Pilates", subtitle: "Core and control"),
                    TraiSuggestion("HIIT", subtitle: "Intervals and conditioning"),
                    TraiSuggestion("Mobility", subtitle: "Joint health and movement"),
                    TraiSuggestion("Mixed", subtitle: "Blend multiple session types")
                ],
                selectionMode: .multiple,
                placeholder: "Or describe any custom split or activity mix..."
            )

        case .experience:
            return TraiQuestionConfig(
                id: rawValue,
                question: "How would you describe your experience level?",
                suggestions: [
                    TraiSuggestion("Beginner", subtitle: "New to working out"),
                    TraiSuggestion("Intermediate", subtitle: "1-3 years of training"),
                    TraiSuggestion("Advanced", subtitle: "3+ years, solid form")
                ],
                selectionMode: .single,
                placeholder: "Or tell me more about your background..."
            )

        case .equipment:
            return TraiQuestionConfig(
                id: rawValue,
                question: "What equipment do you have access to?",
                suggestions: [
                    TraiSuggestion("Full Gym", subtitle: "Machines, cables, free weights"),
                    TraiSuggestion("Home - Dumbbells", subtitle: "Basic dumbbells and bench"),
                    TraiSuggestion("Home - Full Setup", subtitle: "Rack, barbell, weights"),
                    TraiSuggestion("Bodyweight Only", subtitle: "No equipment needed")
                ],
                selectionMode: .single,
                placeholder: "Or describe what you have..."
            )

        case .schedule:
            return TraiQuestionConfig(
                id: rawValue,
                question: "How many days per week can you train?",
                suggestions: [
                    TraiSuggestion("2 days"),
                    TraiSuggestion("3 days"),
                    TraiSuggestion("4 days"),
                    TraiSuggestion("5 days"),
                    TraiSuggestion("6 days"),
                    TraiSuggestion("Flexible")
                ],
                selectionMode: .single,
                placeholder: "Or tell me about your schedule..."
            )

        case .cardio:
            return TraiQuestionConfig(
                id: rawValue,
                question: "Any specific modalities you want included?",
                suggestions: [
                    TraiSuggestion("Running"),
                    TraiSuggestion("Cycling"),
                    TraiSuggestion("Swimming"),
                    TraiSuggestion("Climbing"),
                    TraiSuggestion("Yoga"),
                    TraiSuggestion("Pilates"),
                    TraiSuggestion("Rowing"),
                    TraiSuggestion("Walking"),
                    TraiSuggestion("Anything works", isSkip: true)
                ],
                selectionMode: .multiple,
                placeholder: "Or describe the modalities you want..."
            )

        case .goals:
            return TraiQuestionConfig(
                id: rawValue,
                question: "Do you have any specific fitness goals?",
                suggestions: goalSuggestions,
                selectionMode: .multiple,
                placeholder: "Type your goal...",
                skipText: "No specific goal"
            )

        case .injuries:
            return TraiQuestionConfig(
                id: rawValue,
                question: "Any injuries or limitations I should know about?",
                suggestions: [
                    TraiSuggestion("Bad knee"),
                    TraiSuggestion("Lower back issues"),
                    TraiSuggestion("Shoulder problem"),
                    TraiSuggestion("Wrist pain"),
                    TraiSuggestion("No injuries", isSkip: true)
                ],
                selectionMode: .single,
                placeholder: "Describe any limitations..."
            )

        }
    }

    // Dynamic suggestions based on workout type
    private var goalSuggestions: [TraiSuggestion] {
        [
            TraiSuggestion("Do a pull-up"),
            TraiSuggestion("Bench my bodyweight"),
            TraiSuggestion("See my abs"),
            TraiSuggestion("Get stronger overall"),
            TraiSuggestion("Build muscle"),
            TraiSuggestion("Improve endurance"),
            TraiSuggestion("No specific goal", isSkip: true)
        ]
    }

    /// Whether this question should be shown based on user's previous answers
    func shouldShow(given answers: TraiCollectedAnswers) -> Bool {
        switch self {
        case .cardio:
            // Show the modality follow-up for anything beyond pure strength.
            let workoutTypes = answers.answers(for: WorkoutPlanQuestion.workoutType.rawValue)
            guard !workoutTypes.isEmpty else { return false }
            return !workoutTypes.allSatisfy { $0 == "Strength" }

        default:
            return true
        }
    }
}

// MARK: - Chat Message for Refinement

/// Simple message type for workout plan refinement conversations
struct WorkoutPlanChatMessage {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Session Duration Config

/// Configuration for session duration question (separate from main questions)
struct SessionDurationConfig {
    static let question = TraiQuestionConfig(
        id: "sessionDuration",
        question: "How long do you want each workout to be?",
        suggestions: [
            TraiSuggestion("30 min"),
            TraiSuggestion("45 min"),
            TraiSuggestion("60 min"),
            TraiSuggestion("90 min")
        ],
        selectionMode: .single,
        placeholder: "Or specify a duration..."
    )
}
