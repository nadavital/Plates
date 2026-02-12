//
//  TraiCoachTonePrompting.swift
//  Trai
//
//  Shared tone utilities so Pulse and chat surfaces use one coach voice.
//

import Foundation

extension TraiCoachTone {
    nonisolated static let storageKey = "trai_coach_tone"

    nonisolated static var sharedPreference: TraiCoachTone {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return resolve(rawValue: raw)
    }

    nonisolated static func resolve(rawValue: String?) -> TraiCoachTone {
        guard let rawValue else { return .encouraging }
        return TraiCoachTone(rawValue: rawValue) ?? .encouraging
    }

    nonisolated var chatStylePrompt: String {
        switch self {
        case .encouraging:
            return "Lead with upbeat support, acknowledge effort, and keep momentum high without sounding cheesy."
        case .balanced:
            return "Use calm, steady coaching language that balances encouragement with practical next steps."
        case .direct:
            return "Be concise and straightforward. Prioritize clarity and action, with minimal motivational padding."
        }
    }

    nonisolated var pulseStylePrompt: String {
        switch self {
        case .encouraging:
            return "Tone should feel uplifting and confident, focusing on momentum."
        case .balanced:
            return "Tone should feel grounded, practical, and supportive."
        case .direct:
            return "Tone should be crisp, no-fluff, and action-oriented."
        }
    }

    nonisolated var primingReply: String {
        switch self {
        case .encouraging:
            return "Hey, nice to see you. What do you want to work on?"
        case .balanced:
            return "What do you want to focus on right now?"
        case .direct:
            return "What do you need?"
        }
    }

    nonisolated var followUpInstructionSuffix: String {
        "Use this tone profile: \(chatStylePrompt)"
    }
}
