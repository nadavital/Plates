//
//  OnboardingTheme.swift
//  Trai
//
//  Shared design system for onboarding screens
//

import SwiftUI

// MARK: - Gradients

enum OnboardingGradient {
    static let primary = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let background = LinearGradient(
        colors: [
            Color(.systemBackground),
            Color.accentColor.opacity(0.05)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let card = LinearGradient(
        colors: [
            Color(.secondarySystemBackground),
            Color(.secondarySystemBackground).opacity(0.8)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Animated Background

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.1),
                TraiColors.coral.opacity(0.06),
                Color.accentColor.opacity(0.08)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Onboarding Background

struct OnboardingAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    TraiColors.coral.opacity(colorScheme == .dark ? 0.08 : 0.18),
                    TraiColors.flame.opacity(colorScheme == .dark ? 0.05 : 0.12),
                    Color(.systemBackground).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.15),
                    Color(.systemBackground).opacity(0.65),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Section Header

struct OnboardingSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

// MARK: - Tinted Onboarding Glass

private struct OnboardingTintedGlassModifier: ViewModifier {
    let tint: Color
    let isSelected: Bool
    let cornerRadius: CGFloat
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(
                isInteractive
                    ? .regular.tint(tint.opacity(isSelected ? 0.62 : 0.28)).interactive()
                    : .regular.tint(tint.opacity(isSelected ? 0.46 : 0.18)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.42 : 0.18), lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(
                color: isSelected ? tint.opacity(0.14) : .black.opacity(0.03),
                radius: isSelected ? 10 : 5,
                y: isSelected ? 5 : 3
            )
    }
}

extension View {
    func onboardingTintedGlass(
        tint: Color,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 18,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            OnboardingTintedGlassModifier(
                tint: tint,
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                isInteractive: isInteractive
            )
        )
    }

    func onboardingTraiResponseCard(cornerRadius: CGFloat = 18) -> some View {
        padding(14)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

// MARK: - Primary Button Style

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isEnabled {
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
            )
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Selection Card

struct SelectionCard<Content: View>: View {
    let isSelected: Bool
    let content: Content
    let action: () -> Void

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            Color(.secondarySystemBackground)
                        }
                    }
                )
                .clipShape(.rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.gray.opacity(0.2),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.3) : .clear,
                    radius: 8,
                    y: 4
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Onboarding Choice Card

struct OnboardingChoiceCard: View {
    let title: String
    var hint: String?
    let iconName: String
    let tint: Color
    let isSelected: Bool
    var minHeight: CGFloat = 112
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.cardSelected()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(tint.opacity(0.3))
                            .frame(width: 52, height: 52)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(tint.opacity(isSelected ? 0.95 : 0.78))
                        .frame(width: 46, height: 46)

                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(isSelected ? 1.08 : 1)
                }

                VStack(spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .background(.thinMaterial, in: Circle())
                        .padding(10)
                }
            }
            .onboardingTintedGlass(
                tint: tint,
                isSelected: isSelected,
                cornerRadius: 18,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - Animated Icon

struct AnimatedIcon: View {
    let systemName: String
    let size: CGFloat
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .scaleEffect(isAnimating ? 1.05 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Progress Dots

struct OnboardingProgressDots: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4), value: currentStep)
            }
        }
    }
}

// MARK: - Floating Elements (decorative)

struct FloatingElement: View {
    let delay: Double
    @State private var offset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.1))
            .frame(width: 100, height: 100)
            .blur(radius: 30)
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    offset = 20
                }
            }
    }
}

// MARK: - Input Field Style

struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .keyboardType(keyboardType)
    }
}

// MARK: - Chip/Tag Style

struct OnboardingChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .glassEffect(
                .regular.tint(Color.accentColor.opacity(isSelected ? 0.24 : 0.08)).interactive(),
                in: .capsule
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.22),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Extensions

extension View {
    func onboardingCard() -> some View {
        self
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 20))
    }

    func appearAnimation(delay: Double = 0) -> some View {
        self
            .modifier(AppearAnimationModifier(delay: delay))
    }
}

struct AppearAnimationModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(.spring(response: 0.6).delay(delay)) {
                    isVisible = true
                }
            }
    }
}
