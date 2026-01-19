//
//  PlanReviewAnimations.swift
//  Trai
//
//  Animation modifiers and confetti effects for plan review
//

import SwiftUI

// MARK: - Rotating Modifier

struct RotatingModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Pulsing Modifier

struct PulsingModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(2 - scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    scale = 1.3
                }
            }
    }
}

// MARK: - Sparkle Modifier

struct SparkleModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.1
                }
            }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPieceView(particle: particle)
                }
            }
            .onAppear {
                createParticles(in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func createParticles(in size: CGSize) {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint, .cyan]
        let shapes: [ConfettiShape] = [.circle, .rectangle, .star]

        // Create more particles spread across the full width
        for _ in 0..<100 {
            let startX = CGFloat.random(in: -20...(size.width + 20))
            let particle = ConfettiParticle(
                position: CGPoint(x: startX, y: CGFloat.random(in: -50...(-10))),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 8...16),
                shape: shapes.randomElement()!,
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: 180...720)
            )
            particles.append(particle)
        }

        // Animate particles falling with varied timing
        for index in particles.indices {
            let delay = Double.random(in: 0...0.8)
            let duration = Double.random(in: 2.0...3.5)

            withAnimation(.easeIn(duration: duration).delay(delay)) {
                particles[index].position.y = size.height + 100
                particles[index].position.x += CGFloat.random(in: -150...150)
                particles[index].rotation += particles[index].rotationSpeed
            }

            withAnimation(.easeIn(duration: duration * 0.6).delay(delay + duration * 0.6)) {
                particles[index].opacity = 0
            }
        }
    }
}

// MARK: - Confetti Shape

enum ConfettiShape {
    case circle, rectangle, star
}

// MARK: - Confetti Particle

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    let shape: ConfettiShape
    var rotation: Double
    let rotationSpeed: Double
    var opacity: Double = 1
}

// MARK: - Confetti Piece View

struct ConfettiPieceView: View {
    let particle: ConfettiParticle

    var body: some View {
        Group {
            switch particle.shape {
            case .circle:
                Circle()
                    .fill(particle.color)
            case .rectangle:
                Rectangle()
                    .fill(particle.color)
            case .star:
                Image(systemName: "star.fill")
                    .foregroundStyle(particle.color)
            }
        }
        .frame(width: particle.size, height: particle.shape == .rectangle ? particle.size * 0.6 : particle.size)
        .rotationEffect(.degrees(particle.rotation))
        .position(particle.position)
        .opacity(particle.opacity)
    }
}
