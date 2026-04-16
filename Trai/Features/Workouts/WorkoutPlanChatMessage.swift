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
    case schedule
    case equipment
    case background
    case constraints

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

        case .schedule:
            return TraiQuestionConfig(
                id: rawValue,
                question: "What does your week realistically look like for training?",
                suggestions: [
                    TraiSuggestion("2 days", subtitle: "Keep it minimal and sustainable"),
                    TraiSuggestion("3 days", subtitle: "A balanced weekly rhythm"),
                    TraiSuggestion("4 days", subtitle: "More structure and variety"),
                    TraiSuggestion("5 days", subtitle: "High-frequency training week"),
                    TraiSuggestion("Flexible", subtitle: "Let Trai adapt the structure")
                ],
                selectionMode: .single,
                placeholder: "Mention your schedule, session length, or anything else that matters..."
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

        case .background:
            return TraiQuestionConfig(
                id: rawValue,
                question: "What should I know about your training background?",
                suggestions: [
                    TraiSuggestion("Beginner", subtitle: "I need simple, approachable structure"),
                    TraiSuggestion("Returning", subtitle: "I’ve trained before but I’m rebuilding"),
                    TraiSuggestion("Intermediate", subtitle: "I know the basics and can handle volume"),
                    TraiSuggestion("Advanced", subtitle: "I want something specific and challenging")
                ],
                selectionMode: .single,
                placeholder: "Tell me about your experience, current fitness, or sport background..."
            )

        case .constraints:
            return TraiQuestionConfig(
                id: rawValue,
                question: "Anything else I should build around?",
                suggestions: [
                    TraiSuggestion("Short sessions", subtitle: "Keep workouts efficient"),
                    TraiSuggestion("Need cardio included", subtitle: "Make conditioning part of the plan"),
                    TraiSuggestion("Low impact", subtitle: "Be mindful of joints and recovery"),
                    TraiSuggestion("Want variety", subtitle: "Avoid repetitive weeks"),
                    TraiSuggestion("Working around an injury", subtitle: "Adjust exercise choices"),
                    TraiSuggestion("Let Trai decide", isSkip: true)
                ],
                selectionMode: .multiple,
                placeholder: "Share goals, limitations, favorite activities, or anything Trai should optimize around..."
            )
        }
    }

    /// Whether this question should be shown based on user's previous answers
    func shouldShow(given answers: TraiCollectedAnswers) -> Bool {
        true
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
