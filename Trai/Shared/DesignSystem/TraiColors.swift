//
//  TraiColors.swift
//  Trai
//
//  Brand palette extracted from TraiLensPalette.energy for app-wide use.
//

import SwiftUI

enum TraiColors {
    /// Deep Red — the anchor tone
    static let ember = Color(red: 0.85, green: 0.25, blue: 0.20)

    /// Red-Orange — warm midtone
    static let flame = Color(red: 0.95, green: 0.40, blue: 0.25)

    /// Bright Orange — energetic highlight
    static let blaze = Color(red: 0.98, green: 0.55, blue: 0.30)

    /// Coral Red — soft warmth
    static let coral = Color(red: 0.90, green: 0.35, blue: 0.28)

    /// The brand gradient for hero elements and CTAs
    static let brandGradient = LinearGradient(
        colors: [ember, flame, blaze],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A subtler 2-color brand gradient for secondary uses
    static let warmGradient = LinearGradient(
        colors: [flame, coral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
