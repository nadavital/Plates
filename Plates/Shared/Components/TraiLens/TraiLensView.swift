//
//  TraiLensView.swift
//  Plates
//
//  Animated liquid lens for Trai's visual identity
//

import SwiftUI

struct TraiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var baseSpeedX: CGFloat
    var baseSpeedY: CGFloat
}

/// Color palette options for Trai's lens
public enum TraiLensPalette: String, CaseIterable, Identifiable {
    case energy = "Energy"      // Red/orange - default for fitness
    case focus = "Focus"        // Blue/purple - calm concentration
    case vitality = "Vitality"  // Green/teal - health & wellness
    case warmth = "Warmth"      // Coral/peach - friendly & approachable

    public var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .energy:
            return [
                Color(red: 0.85, green: 0.25, blue: 0.20),  // Deep Red
                Color(red: 0.95, green: 0.40, blue: 0.25),  // Red-Orange
                Color(red: 0.98, green: 0.55, blue: 0.30),  // Bright Orange
                Color(red: 0.90, green: 0.35, blue: 0.28)   // Coral Red
            ]
        case .focus:
            return [
                Color(red: 0.32, green: 0.18, blue: 0.58),  // Deep Violet
                Color(red: 0.58, green: 0.22, blue: 0.52),  // Magenta
                Color(red: 0.22, green: 0.42, blue: 0.72),  // Electric Blue
                Color(red: 0.42, green: 0.32, blue: 0.68)   // Purple
            ]
        case .vitality:
            return [
                Color(red: 0.18, green: 0.65, blue: 0.55),  // Teal
                Color(red: 0.25, green: 0.75, blue: 0.60),  // Seafoam
                Color(red: 0.35, green: 0.80, blue: 0.50),  // Mint Green
                Color(red: 0.28, green: 0.70, blue: 0.58)   // Aqua
            ]
        case .warmth:
            return [
                Color(red: 0.98, green: 0.52, blue: 0.35),  // Coral
                Color(red: 0.95, green: 0.65, blue: 0.45),  // Peach
                Color(red: 0.90, green: 0.45, blue: 0.50),  // Rose
                Color(red: 0.98, green: 0.60, blue: 0.40)   // Soft Orange
            ]
        }
    }
}

/// The animated liquid lens for Trai
public struct TraiLensView: View {
    let size: CGFloat
    let state: TraiLensState
    let palette: TraiLensPalette

    @State private var particles: [TraiParticle] = []
    @State private var breathingPhase: CGFloat = 0
    @State private var currentBlur: CGFloat = 10
    @State private var currentSpeedMult: CGFloat = 0.5

    private var colors: [Color] {
        palette.colors
    }

    public init(size: CGFloat = 120, state: TraiLensState = .idle, palette: TraiLensPalette = .energy) {
        self.size = size
        self.state = state
        self.palette = palette
    }

    func createParticles() {
        var newParticles: [TraiParticle] = []
        let sizeRange = state.particleSizeRange(forSize: size)
        let targetCount = state.particleCount(forSize: size)

        for _ in 0..<targetCount {
            newParticles.append(TraiParticle(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: sizeRange),
                color: colors.randomElement()!,
                baseSpeedX: CGFloat.random(in: -0.003...0.003),
                baseSpeedY: CGFloat.random(in: -0.003...0.003)
            ))
        }
        particles = newParticles
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                // The liquid core - particles with blur for metaball effect
                Canvas { context, canvasSize in
                    for particle in particles {
                        let rect = CGRect(
                            x: particle.x * canvasSize.width,
                            y: particle.y * canvasSize.height,
                            width: particle.size * 1.5,
                            height: particle.size * 1.5
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(particle.color))
                    }
                }
                .blur(radius: currentBlur)
                .opacity(size < 50 ? 1.0 : 0.9)
                .mask(Circle())

                // The glass lens overlay
                Circle()
                    .fill(.white.opacity(0.01))
                    .glassEffect(.regular, in: .circle)
            }
            .frame(width: size, height: size)
            .scaleEffect(1.0 + breathingOffset)
            .onChange(of: timeline.date) { _, newDate in
                updateParticles()
                breathingPhase = newDate.timeIntervalSinceReferenceDate
            }
            .onChange(of: palette) { _, _ in
                createParticles()
            }
            .onChange(of: state) { _, _ in
                // Smoothly transition particle count
            }
            .onAppear {
                if particles.isEmpty {
                    createParticles()
                }
            }
        }
        .frame(width: size, height: size)
    }

    func updateParticles() {
        // Smooth interpolation for blur and speed
        let targetBlur = state.blurAmount(forSize: size)
        let targetSpeed = state.speedMultiplier
        currentBlur += (targetBlur - currentBlur) * 0.1
        currentSpeedMult += (targetSpeed - currentSpeedMult) * 0.1

        // Dynamic population adjustment
        let targetCount = state.particleCount(forSize: size)
        if particles.count < targetCount {
            let sizeRange = state.particleSizeRange(forSize: size)
            particles.append(TraiParticle(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: sizeRange),
                color: colors.randomElement()!,
                baseSpeedX: CGFloat.random(in: -0.003...0.003),
                baseSpeedY: CGFloat.random(in: -0.003...0.003)
            ))
        } else if particles.count > targetCount {
            particles.removeLast()
        }

        // Update particle positions
        for i in particles.indices {
            particles[i].x += particles[i].baseSpeedX * currentSpeedMult
            particles[i].y += particles[i].baseSpeedY * currentSpeedMult

            // Wrap around for smooth flow
            if particles[i].x < -0.2 { particles[i].x = 1.2 }
            if particles[i].x > 1.2 { particles[i].x = -0.2 }
            if particles[i].y < -0.2 { particles[i].y = 1.2 }
            if particles[i].y > 1.2 { particles[i].y = -0.2 }
        }
    }

    private var breathingOffset: CGFloat {
        sin(breathingPhase * .pi / state.breathingSpeed) * state.breathingAmplitude
    }
}

// MARK: - Static Icon Version

/// Static version of Trai's lens for small contexts (tab bar, message avatars)
public struct TraiLensIcon: View {
    let size: CGFloat
    let palette: TraiLensPalette

    public init(size: CGFloat, palette: TraiLensPalette = .energy) {
        self.size = size
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            // Simplified static gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: palette.colors,
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .blur(radius: size * 0.08)

            // Glass overlay
            Circle()
                .fill(.white.opacity(0.01))
                .glassEffect(.regular, in: .circle)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Adaptive Wrapper

/// Smart wrapper that chooses between animated and static lens based on size
public struct AdaptiveTraiLens: View {
    let size: CGFloat
    let state: TraiLensState
    let palette: TraiLensPalette

    private let animationThreshold: CGFloat = 50

    public init(size: CGFloat, state: TraiLensState = .idle, palette: TraiLensPalette = .energy) {
        self.size = size
        self.state = state
        self.palette = palette
    }

    public var body: some View {
        if size < animationThreshold {
            TraiLensIcon(size: size, palette: palette)
        } else {
            TraiLensView(size: size, state: state, palette: palette)
        }
    }
}

// MARK: - Preview

#Preview("Trai Lens States") {
    ScrollView {
        VStack(spacing: 40) {
            Text("TRAI")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(4)

            TraiLensView(size: 150, state: .idle, palette: .energy)

            HStack(spacing: 30) {
                ForEach(TraiLensPalette.allCases) { palette in
                    VStack {
                        TraiLensView(size: 80, state: .idle, palette: palette)
                        Text(palette.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 20) {
                VStack {
                    TraiLensIcon(size: 32, palette: .energy)
                    Text("Tab")
                        .font(.caption2)
                }
                VStack {
                    TraiLensIcon(size: 24, palette: .energy)
                    Text("Avatar")
                        .font(.caption2)
                }
            }
        }
        .padding(40)
    }
}
