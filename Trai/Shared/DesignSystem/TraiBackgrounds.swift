//
//  TraiBackgrounds.swift
//  Trai
//
//  Warm ambient background modifier that unifies surface appearance.
//

import SwiftUI

// MARK: - Warm Background Modifier

struct TraiWarmBackground: ViewModifier {
    var intensity: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                warmGlow
                    .ignoresSafeArea()
            )
    }

    private var warmGlow: some View {
        LinearGradient(
            colors: [
                warmTint.opacity(effectiveOpacity),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var warmTint: Color {
        colorScheme == .dark
            ? TraiColors.flame
            : TraiColors.coral
    }

    /// ~4% base opacity scaled by intensity, halved in dark mode
    private var effectiveOpacity: Double {
        let base = 0.04 * intensity
        return colorScheme == .dark ? base * 0.5 : base
    }
}

extension View {
    /// Applies a subtle warm ambient glow from the top of the view.
    /// - Parameter intensity: 0.0 (none) to 1.0 (full warmth). Default 0.5.
    func traiBackground(intensity: Double = 0.5) -> some View {
        modifier(TraiWarmBackground(intensity: intensity))
    }
}
