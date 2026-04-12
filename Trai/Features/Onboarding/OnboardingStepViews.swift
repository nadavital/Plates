//
//  OnboardingStepViews.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI

// MARK: - Welcome Step

struct WelcomeStepView: View {
    @Binding var userName: String
    @State private var heroVisible = false
    @State private var titleVisible = false
    @State private var feature1Visible = false
    @State private var feature2Visible = false
    @State private var feature3Visible = false
    @State private var inputSectionVisible = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            // Decorative floating elements with parallax
            floatingDecorations

            // Single scroll view with all content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, 20)
                            .padding(.bottom, 24)

                        featuresSection
                            .padding(.bottom, 28)

                        nameInputSection
                            .id("nameInput")
                            .padding(.bottom, 140) // Space for floating button
                    }
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isNameFocused, initial: false) { _, focused in
                    if focused {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("nameInput", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onAppear {
            startEntranceAnimations()
        }
    }

    private func startEntranceAnimations() {
        // Hero fade in
        withAnimation(.easeOut(duration: 0.5)) {
            heroVisible = true
        }

        // Title fade in
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            titleVisible = true
        }

        // Staggered feature cards
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            feature1Visible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            feature2Visible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            feature3Visible = true
        }

        // Input section
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
            inputSectionVisible = true
        }

    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 14) {
            // The welcome slide uses the lens as a brand mark, so keep it static.
            TraiLensIcon(size: 64, palette: .energy)
                .opacity(heroVisible ? 1 : 0)
                .scaleEffect(heroVisible ? 1 : 0.9)

            VStack(spacing: 6) {
                Text("Welcome to")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Trai")
                    .font(.traiHero(38))
                    .foregroundStyle(.primary)
            }
            .opacity(titleVisible ? 1 : 0)

            Text("Meet Trai, your personal coach\nwho learns and adapts to you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .opacity(titleVisible ? 1 : 0)
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: 10) {
            FeatureRow(
                icon: "sparkles",
                color: TraiColors.flame,
                title: "Personal Plan, Built Fast",
                description: "Answer a few questions and Trai builds targets that match your body and goal."
            )
            .opacity(feature1Visible ? 1 : 0)

            FeatureRow(
                icon: "camera.fill",
                color: TraiColors.blaze,
                title: "Log Meals in Seconds",
                description: "Snap your food, save the meal, and keep your streak moving without manual entry."
            )
            .opacity(feature2Visible ? 1 : 0)

            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                color: .accentColor,
                title: "Coaching That Adapts",
                description: "See clear progress trends and adjust your plan as your routine changes."
            )
            .opacity(feature3Visible ? 1 : 0)
        }
    }

    // MARK: - Name Input Section

    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Let's get started")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isNameFocused ? Color.accentColor : Color(.tertiarySystemBackground))
                        .frame(width: 40, height: 40)

                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isNameFocused ? .white : .secondary)
                }
                .animation(.spring(response: 0.3), value: isNameFocused)

                TextField("Enter your name", text: $userName)
                    .font(.body)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .onChange(of: isNameFocused, initial: false) { _, focused in
                        if focused {
                            HapticManager.lightTap()
                        }
                    }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isNameFocused ? Color.accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .shadow(
                color: isNameFocused ? Color.accentColor.opacity(0.2) : Color.clear,
                radius: 12,
                y: 4
            )
            .animation(.spring(response: 0.3), value: isNameFocused)
        }
        .offset(y: inputSectionVisible ? 0 : 30)
        .opacity(inputSectionVisible ? 1 : 0)
    }

    // MARK: - Floating Decorations

    private var floatingDecorations: some View {
        GeometryReader { geo in
            // Top right blob
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: geo.size.width * 0.5, y: -80)

            // Left middle blob
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 180, height: 180)
                .blur(radius: 45)
                .offset(x: -80, y: geo.size.height * 0.35)

            // Bottom right accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.1), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: geo.size.width * 0.65, y: geo.size.height * 0.55)

            // Subtle bottom left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 140, height: 140)
                .blur(radius: 35)
                .offset(x: -40, y: geo.size.height * 0.7)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    WelcomeStepView(userName: .constant(""))
}
