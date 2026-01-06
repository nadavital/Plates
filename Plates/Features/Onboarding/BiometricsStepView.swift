//
//  BiometricsStepView.swift
//  Plates
//

import SwiftUI

struct BiometricsStepView: View {
    @Binding var dateOfBirth: Date
    @Binding var gender: UserProfile.Gender?
    @Binding var heightValue: String
    @Binding var weightValue: String
    @Binding var targetWeightValue: String
    @Binding var usesMetricHeight: Bool
    @Binding var usesMetricWeight: Bool

    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""

    @State private var headerVisible = false
    @State private var card1Visible = false
    @State private var card2Visible = false
    @State private var card3Visible = false
    @State private var card4Visible = false

    @State private var focusedCard: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 16)

                    VStack(spacing: 18) {
                        birthdayCard
                            .offset(y: card1Visible ? 0 : 30)
                            .opacity(card1Visible ? 1 : 0)

                        genderCard
                            .offset(y: card2Visible ? 0 : 30)
                            .opacity(card2Visible ? 1 : 0)

                        heightCard
                            .id("heightCard")
                            .offset(y: card3Visible ? 0 : 30)
                            .opacity(card3Visible ? 1 : 0)

                        weightCard
                            .id("weightCard")
                            .offset(y: card4Visible ? 0 : 30)
                            .opacity(card4Visible ? 1 : 0)
                    }
                    .padding(.bottom, 140)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedCard, initial: false) { _, card in
                if let card {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(card, anchor: .center)
                    }
                }
            }
        }
        .onAppear {
            startEntranceAnimations()
        }
    }

    private func startEntranceAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
            card1Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2)) {
            card2Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.3)) {
            card3Visible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.4)) {
            card4Visible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.1), lineWidth: 2)
                    .frame(width: 95, height: 95)
                    .scaleEffect(headerVisible ? 1 : 0.5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(headerVisible ? 1 : 0.8)

            Text("About You")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("This helps us calculate your\npersonalized nutrition plan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    // MARK: - Birthday Card

    private var birthdayCard: some View {
        VStack(spacing: 12) {
            Label("Birthday", systemImage: "gift.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.pink)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker(
                "Birthday",
                selection: $dateOfBirth,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 120)
            .clipped()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Gender Card

    private var genderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Biological Sex", systemImage: "figure.stand")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)

                    Text("Used for accurate metabolic calculations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.capsule)
            }

            HStack(spacing: 10) {
                ForEach(UserProfile.Gender.allCases) { genderOption in
                    GenderSelectionButton(
                        gender: genderOption,
                        isSelected: gender == genderOption
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            gender = genderOption
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Height Card

    private var heightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Height", systemImage: "ruler.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                Spacer()

                UnitToggle(usesMetric: $usesMetricHeight, metricLabel: "cm", imperialLabel: "ft")
            }

            if usesMetricHeight {
                MeasurementInput(
                    placeholder: "170",
                    value: $heightValue,
                    unit: "cm",
                    onFocus: { focusedCard = "heightCard" }
                )
            } else {
                HStack(spacing: 12) {
                    MeasurementInput(
                        placeholder: "5",
                        value: $heightFeet,
                        unit: "ft",
                        onFocus: { focusedCard = "heightCard" }
                    )
                    MeasurementInput(
                        placeholder: "10",
                        value: $heightInches,
                        unit: "in",
                        onFocus: { focusedCard = "heightCard" }
                    )
                }
                .onChange(of: heightFeet, initial: false) { _, _ in
                    updateHeightFromImperial()
                }
                .onChange(of: heightInches, initial: false) { _, _ in
                    updateHeightFromImperial()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Weight Card

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Spacer()

                UnitToggle(usesMetric: $usesMetricWeight, metricLabel: "kg", imperialLabel: "lbs")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current weight")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MeasurementInput(
                    placeholder: usesMetricWeight ? "70" : "155",
                    value: $weightValue,
                    unit: usesMetricWeight ? "kg" : "lbs",
                    onFocus: { focusedCard = "weightCard" }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target weight")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.capsule)
                }

                MeasurementInput(
                    placeholder: usesMetricWeight ? "65" : "145",
                    value: $targetWeightValue,
                    unit: usesMetricWeight ? "kg" : "lbs",
                    onFocus: { focusedCard = "weightCard" }
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func updateHeightFromImperial() {
        guard let feet = Double(heightFeet) else {
            heightValue = ""
            return
        }
        let inches = Double(heightInches) ?? 0
        let totalInches = (feet * 12) + inches
        let cm = totalInches * 2.54
        heightValue = String(format: "%.0f", cm)
    }
}

#Preview {
    BiometricsStepView(
        dateOfBirth: .constant(Calendar.current.date(byAdding: .year, value: -25, to: Date())!),
        gender: .constant(.notSpecified),
        heightValue: .constant(""),
        weightValue: .constant(""),
        targetWeightValue: .constant(""),
        usesMetricHeight: .constant(true),
        usesMetricWeight: .constant(true)
    )
}
