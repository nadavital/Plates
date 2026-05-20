//
//  BiometricsStepView.swift
//  Trai
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
    var showsTargetWeight: Bool = true

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
                VStack(spacing: 18) {
                    headerSection
                        .padding(.top, 10)

                    VStack(spacing: 14) {
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
            syncDisplayedMeasurements()
        }
        .onChange(of: usesMetricHeight, initial: false) { _, isMetric in
            handleHeightUnitChange(isMetric: isMetric)
        }
        .onChange(of: usesMetricWeight, initial: false) { oldValue, newValue in
            handleWeightUnitChange(fromMetric: oldValue, toMetric: newValue)
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
        OnboardingTraiHeader(
            title: "Enter your basics.",
            lensSize: 56
        )
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : -20)
    }

    // MARK: - Birthday Card

    private var birthdayCard: some View {
        HStack(spacing: 16) {
            Label("Birthday", systemImage: "gift.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.accent)

            Spacer()

            DatePicker(
                "Birthday",
                selection: $dateOfBirth,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .traiCard(cornerRadius: 16)
    }

    // MARK: - Gender Card

    private var genderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Biological Sex", systemImage: "figure.stand")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.accent)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .traiCard(cornerRadius: 16)
    }

    // MARK: - Height Card

    private var heightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Height", systemImage: "ruler.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.accent)

                Spacer()

                UnitToggle(usesMetric: $usesMetricHeight, metricLabel: "cm", imperialLabel: "ft")
            }

            if usesMetricHeight {
                MeasurementInput(
                    placeholder: "170",
                    value: $heightValue,
                    unit: "cm",
                    accessibilityIdentifier: "onboardingHeightField",
                    onFocus: { focusedCard = "heightCard" }
                )
            } else {
                HStack(spacing: 12) {
                    MeasurementInput(
                        placeholder: "5",
                        value: $heightFeet,
                        unit: "ft",
                        accessibilityIdentifier: "onboardingHeightFeetField",
                        onFocus: { focusedCard = "heightCard" }
                    )
                    MeasurementInput(
                        placeholder: "10",
                        value: $heightInches,
                        unit: "in",
                        accessibilityIdentifier: "onboardingHeightInchesField",
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .traiCard(cornerRadius: 16)
    }

    // MARK: - Weight Card

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.accent)

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
                    accessibilityIdentifier: "onboardingCurrentWeightField",
                    onFocus: { focusedCard = "weightCard" }
                )
            }

            if showsTargetWeight {
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
                        accessibilityIdentifier: "onboardingTargetWeightField",
                        onFocus: { focusedCard = "weightCard" }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .traiCard(cornerRadius: 16)
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

    private func syncDisplayedMeasurements() {
        if usesMetricHeight {
            heightFeet = ""
            heightInches = ""
        } else {
            syncImperialHeightFieldsFromStoredCentimeters()
        }
    }

    private func handleHeightUnitChange(isMetric: Bool) {
        if isMetric {
            heightFeet = ""
            heightInches = ""
        } else {
            syncImperialHeightFieldsFromStoredCentimeters()
        }
    }

    private func syncImperialHeightFieldsFromStoredCentimeters() {
        guard let centimeters = Double(heightValue), centimeters > 0 else {
            heightFeet = ""
            heightInches = ""
            return
        }

        let roundedTotalInches = Int((centimeters / 2.54).rounded())
        let feet = roundedTotalInches / 12
        let inches = roundedTotalInches % 12

        heightFeet = String(feet)
        heightInches = String(inches)
    }

    private func handleWeightUnitChange(fromMetric: Bool, toMetric: Bool) {
        guard fromMetric != toMetric else { return }

        weightValue = convertedWeightString(weightValue, fromMetric: fromMetric, toMetric: toMetric)
        targetWeightValue = convertedWeightString(targetWeightValue, fromMetric: fromMetric, toMetric: toMetric)
    }

    private func convertedWeightString(_ rawValue: String, fromMetric: Bool, toMetric: Bool) -> String {
        guard let value = Double(rawValue), value > 0 else { return rawValue }

        let convertedValue: Double
        if fromMetric && !toMetric {
            convertedValue = value / 0.453592
        } else if !fromMetric && toMetric {
            convertedValue = value * 0.453592
        } else {
            convertedValue = value
        }

        let roundedValue = (convertedValue * 10).rounded() / 10
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }
        return String(format: "%.1f", roundedValue)
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
        usesMetricWeight: .constant(true),
        showsTargetWeight: true
    )
}
