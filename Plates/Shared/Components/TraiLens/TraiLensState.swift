//
//  TraiLensState.swift
//  Plates
//
//  Animation states for Trai's visual identity
//

import SwiftUI

/// The focus states of Trai's lens
public enum TraiLensState: Equatable, Hashable {
    /// Gentle breathing - calm, waiting
    case idle

    /// Deep breath - receptive, user is typing
    case listening

    /// Fast breathing - processing, generating response
    case thinking

    /// Steady flow - streaming response
    case answering

    // MARK: - Physics Parameters

    var speedMultiplier: CGFloat {
        switch self {
        case .idle: return 0.5
        case .listening: return 0.2
        case .thinking: return 3.0
        case .answering: return 1.2
        }
    }

    func blurAmount(forSize size: CGFloat) -> CGFloat {
        let referenceSize: CGFloat = 120
        let baseBlur: CGFloat

        switch self {
        case .idle: baseBlur = 10
        case .listening: baseBlur = 4
        case .thinking: baseBlur = 15
        case .answering: baseBlur = 8
        }

        let scaledBlur = baseBlur * (size / referenceSize)
        return max(2.0, scaledBlur)
    }

    func particleCount(forSize size: CGFloat) -> Int {
        let baseCount: Int

        switch self {
        case .idle: baseCount = 50
        case .listening: baseCount = 65
        case .thinking: baseCount = 80
        case .answering: baseCount = 60
        }

        if size < 50 {
            return max(4, Int(Double(baseCount) * 0.15))
        }

        return baseCount
    }

    func particleSizeRange(forSize size: CGFloat) -> ClosedRange<CGFloat> {
        if size < 50 {
            return (size * 0.25)...(size * 0.40)
        } else {
            return (size * 0.06)...(size * 0.14)
        }
    }

    var breathingAmplitude: CGFloat {
        switch self {
        case .idle: return 0.03
        case .listening: return 0.08
        case .thinking: return 0.06
        case .answering: return 0.05
        }
    }

    var breathingSpeed: CGFloat {
        switch self {
        case .idle: return 2.0
        case .listening: return 3.0
        case .thinking: return 1.0
        case .answering: return 1.8
        }
    }
}
