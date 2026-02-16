//
//  TraiDesignSystem.swift
//  Trai
//
//  Centralized design tokens for spacing, radii, gradients, and animation.
//

import SwiftUI

// MARK: - Spacing

enum TraiSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Corner Radii

enum TraiRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

// MARK: - Animation

enum TraiAnimation {
    static let quick: Animation = .spring(response: 0.25, dampingFraction: 0.8)
    static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
    static let bouncy: Animation = .spring(response: 0.4, dampingFraction: 0.6)
    static let slow: Animation = .spring(response: 0.55, dampingFraction: 0.8)
}

// MARK: - Gradients

enum TraiGradient {
    /// Vibrant gradient for primary CTA buttons
    static func action(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Richer gradient for action buttons with a secondary color shift
    static func actionVibrant(_ from: Color, _ to: Color) -> LinearGradient {
        LinearGradient(
            colors: [from, to],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle surface tint for card backgrounds
    static func cardSurface(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.06),
                color.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Progress bar gradient
    static func progress(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Macro ring gradient for richer circular progress
    static func ring(_ color: Color) -> AngularGradient {
        AngularGradient(
            colors: [color, color.opacity(0.6), color],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }
}

// MARK: - Typography Helpers

extension Font {
    /// Bold rounded display font for hero metrics
    static func traiHero(_ size: CGFloat = 36) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Bold rounded font for card titles and numbers
    static func traiBold(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Semibold rounded font for section headers
    static func traiHeadline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Medium rounded font for labels
    static func traiLabel(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Gradient Button Style

/// A vibrant gradient button with press-scale and haptic feedback
struct TraiGradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    var cornerRadius: CGFloat = TraiRadius.medium

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.traiHeadline())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(gradient)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0 : 0.12),
                radius: configuration.isPressed ? 2 : 8,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(TraiAnimation.quick, value: configuration.isPressed)
    }
}

// MARK: - Press Style

/// Subtle press-scale animation for interactive cards and buttons
struct TraiPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(TraiAnimation.quick, value: configuration.isPressed)
    }
}

// MARK: - Card Background Modifier

struct TraiCardBackground: ViewModifier {
    var tintColor: Color?
    var glow: TraiCardGlow?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: TraiRadius.medium)
                        .fill(cardFill)

                    if let glow {
                        TraiCardGlowBackground(glow: glow)
                            .clipShape(.rect(cornerRadius: TraiRadius.medium))
                    } else if let tintColor {
                        RoundedRectangle(cornerRadius: TraiRadius.medium)
                            .fill(TraiGradient.cardSurface(tintColor))
                    }
                }
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    y: shadowY
                )
            )
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(.secondarySystemBackground)
            : .white
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.06)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 4 : 8
    }

    private var shadowY: CGFloat {
        colorScheme == .dark ? 2 : 4
    }
}

extension View {
    func traiCard(tint: Color? = nil) -> some View {
        modifier(TraiCardBackground(tintColor: tint))
    }

    /// Card with organic radial gradient glow background.
    func traiCard(glow: TraiCardGlow) -> some View {
        modifier(TraiCardBackground(glow: glow))
    }
}

// MARK: - Card Glow System

/// Defines the organic radial gradient treatment for a card.
/// Each glow uses 2-3 offset radial gradients that blur and merge
/// to create a rich, non-geometric background.
struct TraiCardGlow {
    let spots: [GlowSpot]

    struct GlowSpot {
        let color: Color
        let center: UnitPoint
        let radius: CGFloat   // fraction of card width (0...1)
        let opacity: Double
    }
}

extension TraiCardGlow {
    /// Green-teal glow for calorie/nutrition cards
    static let nutrition = TraiCardGlow(spots: [
        GlowSpot(color: .green, center: UnitPoint(x: 0.2, y: 0.3), radius: 0.7, opacity: 0.10),
        GlowSpot(color: .teal, center: UnitPoint(x: 0.8, y: 0.7), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .mint, center: UnitPoint(x: 0.5, y: 0.1), radius: 0.4, opacity: 0.05),
    ])

    /// Multi-color glow for macros (protein/carbs/fat)
    static let macros = TraiCardGlow(spots: [
        GlowSpot(color: .orange, center: UnitPoint(x: 0.15, y: 0.4), radius: 0.5, opacity: 0.09),
        GlowSpot(color: .blue, center: UnitPoint(x: 0.7, y: 0.2), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .pink, center: UnitPoint(x: 0.85, y: 0.8), radius: 0.45, opacity: 0.07),
    ])

    /// Orange-amber glow for workout/activity cards
    static let activity = TraiCardGlow(spots: [
        GlowSpot(color: .orange, center: UnitPoint(x: 0.3, y: 0.2), radius: 0.6, opacity: 0.10),
        GlowSpot(color: .yellow, center: UnitPoint(x: 0.75, y: 0.6), radius: 0.5, opacity: 0.07),
        GlowSpot(color: .red, center: UnitPoint(x: 0.1, y: 0.8), radius: 0.4, opacity: 0.06),
    ])

    /// Blue-indigo glow for weight/body metrics
    static let body = TraiCardGlow(spots: [
        GlowSpot(color: Color.accentColor, center: UnitPoint(x: 0.25, y: 0.3), radius: 0.6, opacity: 0.10),
        GlowSpot(color: .indigo, center: UnitPoint(x: 0.8, y: 0.5), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .purple, center: UnitPoint(x: 0.5, y: 0.9), radius: 0.4, opacity: 0.05),
    ])

    /// Warm glow for quick actions
    static let quickActions = TraiCardGlow(spots: [
        GlowSpot(color: .green, center: UnitPoint(x: 0.1, y: 0.5), radius: 0.45, opacity: 0.08),
        GlowSpot(color: .orange, center: UnitPoint(x: 0.5, y: 0.3), radius: 0.45, opacity: 0.08),
        GlowSpot(color: .blue, center: UnitPoint(x: 0.9, y: 0.5), radius: 0.45, opacity: 0.08),
    ])

    /// Purple-cyan glow for workout trends
    static let trends = TraiCardGlow(spots: [
        GlowSpot(color: .orange, center: UnitPoint(x: 0.2, y: 0.2), radius: 0.55, opacity: 0.09),
        GlowSpot(color: .purple, center: UnitPoint(x: 0.8, y: 0.4), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .green, center: UnitPoint(x: 0.4, y: 0.9), radius: 0.4, opacity: 0.06),
    ])

    /// Warm amber glow for reminders/schedule
    static let reminders = TraiCardGlow(spots: [
        GlowSpot(color: .yellow, center: UnitPoint(x: 0.3, y: 0.2), radius: 0.55, opacity: 0.09),
        GlowSpot(color: .orange, center: UnitPoint(x: 0.75, y: 0.6), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .pink, center: UnitPoint(x: 0.15, y: 0.8), radius: 0.4, opacity: 0.05),
    ])

    /// Warm energetic glow for workout template cards
    static let workout = TraiCardGlow(spots: [
        GlowSpot(color: .orange, center: UnitPoint(x: 0.15, y: 0.2), radius: 0.6, opacity: 0.12),
        GlowSpot(color: .green, center: UnitPoint(x: 0.85, y: 0.4), radius: 0.5, opacity: 0.08),
        GlowSpot(color: .blue, center: UnitPoint(x: 0.4, y: 0.85), radius: 0.45, opacity: 0.06),
    ])

    /// Cyan-blue glow for exercise/workout cards
    static let exercise = TraiCardGlow(spots: [
        GlowSpot(color: .cyan, center: UnitPoint(x: 0.2, y: 0.3), radius: 0.6, opacity: 0.09),
        GlowSpot(color: .blue, center: UnitPoint(x: 0.8, y: 0.5), radius: 0.5, opacity: 0.07),
        GlowSpot(color: .purple, center: UnitPoint(x: 0.5, y: 0.9), radius: 0.4, opacity: 0.05),
    ])

    /// Green glow for food/camera review
    static let food = TraiCardGlow(spots: [
        GlowSpot(color: .green, center: UnitPoint(x: 0.3, y: 0.3), radius: 0.6, opacity: 0.09),
        GlowSpot(color: .mint, center: UnitPoint(x: 0.7, y: 0.7), radius: 0.5, opacity: 0.07),
        GlowSpot(color: .yellow, center: UnitPoint(x: 0.15, y: 0.8), radius: 0.35, opacity: 0.05),
    ])

    /// Creates a glow from a single semantic color
    static func color(_ color: Color) -> TraiCardGlow {
        TraiCardGlow(spots: [
            GlowSpot(color: color, center: UnitPoint(x: 0.25, y: 0.3), radius: 0.6, opacity: 0.10),
            GlowSpot(color: color, center: UnitPoint(x: 0.8, y: 0.65), radius: 0.45, opacity: 0.07),
        ])
    }
}

/// Renders the organic radial gradient glow spots.
private struct TraiCardGlowBackground: View {
    let glow: TraiCardGlow
    @Environment(\.colorScheme) private var colorScheme

    private var intensityScale: Double {
        colorScheme == .dark ? 1.4 : 1.0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(glow.spots.indices, id: \.self) { index in
                    let spot = glow.spots[index]
                    RadialGradient(
                        colors: [
                            spot.color.opacity(spot.opacity * intensityScale),
                            spot.color.opacity(spot.opacity * 0.3 * intensityScale),
                            Color.clear
                        ],
                        center: spot.center,
                        startRadius: 0,
                        endRadius: geometry.size.width * spot.radius
                    )
                }
            }
            .blur(radius: 20)
        }
    }
}
