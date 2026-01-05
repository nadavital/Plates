//
//  SummaryStepView.swift
//  Plates
//

import SwiftUI

struct SummaryStepView: View {
    let userName: String
    let dateOfBirth: Date
    let gender: UserProfile.Gender?
    let heightValue: String
    let weightValue: String
    let targetWeightValue: String
    let usesMetricHeight: Bool
    let usesMetricWeight: Bool
    let activityLevel: UserProfile.ActivityLevel?
    let activityNotes: String
    let selectedGoal: UserProfile.GoalType?
    let dietaryRestrictions: Set<DietaryRestriction>
    let additionalNotes: String

    @State private var headerVisible = false
    @State private var cardsVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                    .padding(.top, 16)

                summaryCards
                    .opacity(cardsVisible ? 1 : 0)

                confirmationNote
                    .opacity(cardsVisible ? 1 : 0)
                    .padding(.bottom, 140)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startEntranceAnimations()
        }
    }

    private func startEntranceAnimations() {
        withAnimation(.easeOut(duration: 0.4)) {
            headerVisible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            cardsVisible = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }
            .opacity(headerVisible ? 1 : 0)
            .scaleEffect(headerVisible ? 1 : 0.9)

            Text("Review Your Info")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .opacity(headerVisible ? 1 : 0)

            Text("Make sure everything looks correct\nbefore we create your plan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(headerVisible ? 1 : 0)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        VStack(spacing: 14) {
            // Profile card
            SummaryCard(title: "Profile", icon: "person.fill", color: .blue) {
                SummaryRow(label: "Name", value: userName)
                SummaryRow(label: "Age", value: "\(calculateAge()) years old")
                if let gender = gender {
                    SummaryRow(label: "Sex", value: gender.displayName)
                }
            }

            // Body card
            SummaryCard(title: "Body", icon: "figure.stand", color: .orange) {
                SummaryRow(label: "Height", value: formatHeight())
                SummaryRow(label: "Current Weight", value: formatWeight(weightValue))
                if !targetWeightValue.isEmpty {
                    SummaryRow(label: "Target Weight", value: formatWeight(targetWeightValue))
                }
            }

            // Activity card
            SummaryCard(title: "Activity", icon: "flame.fill", color: .red) {
                if let activityLevel {
                    SummaryRow(label: "Level", value: activityLevel.displayName)
                }
                if !activityNotes.isEmpty {
                    SummaryRow(label: "Details", value: activityNotes)
                }
            }

            // Goals card
            SummaryCard(title: "Goals", icon: "target", color: .green) {
                if let selectedGoal {
                    SummaryRow(label: "Primary Goal", value: selectedGoal.displayName)
                }
                if !dietaryRestrictions.isEmpty {
                    SummaryRow(
                        label: "Dietary",
                        value: dietaryRestrictions.map(\.displayName).sorted().joined(separator: ", ")
                    )
                }
                if !additionalNotes.isEmpty {
                    SummaryRow(label: "Notes", value: additionalNotes)
                }
            }
        }
    }

    // MARK: - Confirmation Note

    private var confirmationNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.purple)

            Text("Trai will use this information to create a personalized nutrition plan just for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.1))
        .clipShape(.rect(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func calculateAge() -> Int {
        let components = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date())
        return components.year ?? 0
    }

    private func formatHeight() -> String {
        if usesMetricHeight {
            return "\(heightValue) cm"
        } else {
            // Convert from stored cm value to feet/inches for display
            if let cm = Double(heightValue) {
                let totalInches = cm / 2.54
                let feet = Int(totalInches / 12)
                let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
                return "\(feet)'\(inches)\""
            }
            return heightValue
        }
    }

    private func formatWeight(_ value: String) -> String {
        guard !value.isEmpty else { return "—" }
        let unit = usesMetricWeight ? "kg" : "lbs"
        return "\(value) \(unit)"
    }
}

// MARK: - Summary Card

struct SummaryCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            VStack(spacing: 8) {
                content
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Summary Row

struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    SummaryStepView(
        userName: "John",
        dateOfBirth: Calendar.current.date(byAdding: .year, value: -25, to: Date())!,
        gender: .male,
        heightValue: "180",
        weightValue: "75",
        targetWeightValue: "70",
        usesMetricHeight: true,
        usesMetricWeight: true,
        activityLevel: .moderate,
        activityNotes: "I go to the gym 4x per week",
        selectedGoal: .loseWeight,
        dietaryRestrictions: [.vegetarian, .glutenFree],
        additionalNotes: ""
    )
}
