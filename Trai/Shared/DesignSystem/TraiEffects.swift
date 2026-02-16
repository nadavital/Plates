//
//  TraiEffects.swift
//  Trai
//
//  Interaction primitives: entrance animations, animated numbers,
//  gradient text, celebration pulse, and shimmer loading.
//

import SwiftUI

// MARK: - Staggered Entrance Animation

struct TraiEntranceModifier: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .onAppear {
                withAnimation(
                    TraiAnimation.standard.delay(Double(index) * 0.06)
                ) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Staggered spring fade+slide entrance for card lists.
    /// - Parameter index: Position in the list (0-based). Each index adds 0.06s delay.
    func traiEntrance(index: Int) -> some View {
        modifier(TraiEntranceModifier(index: index))
    }
}

// MARK: - Animated Number

/// Wraps a numeric `Text` with `.contentTransition(.numericText())` so metrics roll instead of snap.
struct TraiAnimatedNumber: View {
    let value: Int
    var font: Font = .traiBold(28)
    var color: Color? = nil

    var body: some View {
        Text("\(value)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .foregroundStyle(color ?? .primary)
            .animation(TraiAnimation.standard, value: value)
    }
}

/// Animated number for doubles with configurable precision.
struct TraiAnimatedDecimal: View {
    let value: Double
    var fractionLength: Int = 1
    var font: Font = .traiBold(28)
    var color: Color? = nil

    var body: some View {
        Text(value, format: .number.precision(.fractionLength(fractionLength)))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .foregroundStyle(color ?? .primary)
            .animation(TraiAnimation.standard, value: value)
    }
}

// MARK: - Gradient Text

struct TraiGradientTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(TraiColors.brandGradient)
    }
}

extension View {
    /// Applies the brand gradient as foreground for hero numbers and titles.
    func traiGradientText() -> some View {
        modifier(TraiGradientTextModifier())
    }
}

// MARK: - Celebration Pulse

/// Expanding ring + haptic, triggered on goal completions.
struct TraiCelebrationPulse: View {
    let isActive: Bool
    var color: Color = TraiColors.flame

    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
            .onChange(of: isActive) { _, active in
                guard active else { return }
                ringScale = 0.8
                ringOpacity = 0.6
                withAnimation(.easeOut(duration: 0.6)) {
                    ringScale = 1.5
                    ringOpacity = 0
                }
                HapticManager.success()
            }
    }
}

// MARK: - Shimmer

/// Animated gradient sweep for loading skeletons.
struct TraiShimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.15),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 200)
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Adds an animated shimmer sweep for loading states.
    func traiShimmer() -> some View {
        modifier(TraiShimmer())
    }
}
