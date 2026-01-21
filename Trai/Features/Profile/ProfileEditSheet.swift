//
//  ProfileEditSheet.swift
//  Trai
//

import SwiftUI
import SwiftData

struct ProfileEditSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var heightCm: String
    @State private var targetWeightKg: String
    @State private var activityLevel: UserProfile.ActivityLevel
    @State private var showPlanAdjustment = false
    @FocusState private var focusedField: Field?

    enum Field {
        case name, height, targetWeight
    }

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _heightCm = State(initialValue: profile.heightCm.map { "\(Int($0))" } ?? "")
        _targetWeightKg = State(initialValue: profile.targetWeightKg.map { String(format: "%.1f", $0) } ?? "")
        _activityLevel = State(initialValue: profile.activityLevelValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Name
                    nameSection

                    // Body measurements
                    measurementsSection

                    // Activity Level
                    activitySection

                    // Plan adjustment link
                    planSection
                }
                .padding()
                .padding(.bottom, 20)
            }
            .sheet(isPresented: $showPlanAdjustment) {
                PlanAdjustmentSheet(profile: profile)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(!isValid)
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(heightCm) ?? 0) >= 100 &&
        (targetWeightKg.isEmpty || (Double(targetWeightKg) ?? 0) >= 30)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 90, height: 90)

            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 80, height: 80)
                .overlay {
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
        }
        .padding(.top, 8)
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Name", systemImage: "person.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextField("Your name", text: $name)
                .font(.title3)
                .fontWeight(.medium)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focusedField == .name ? Color.accentColor : .clear, lineWidth: 2)
                )
                .focused($focusedField, equals: .name)
        }
    }

    // MARK: - Measurements Section

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Body Measurements", systemImage: "ruler.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                // Height input
                HStack {
                    Image(systemName: "arrow.up.and.down")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    Text("Height")
                        .font(.subheadline)

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("170", text: $heightCm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline)
                            .frame(width: 60)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .height ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            .focused($focusedField, equals: .height)

                        Text("cm")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Target weight (optional)
                HStack {
                    Image(systemName: "target")
                        .font(.body)
                        .foregroundStyle(.green)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target Weight")
                            .font(.subheadline)
                        Text("Optional")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("—", text: $targetWeightKg)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline)
                            .frame(width: 70)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .targetWeight ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            .focused($focusedField, equals: .targetWeight)

                        Text("kg")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Progress indicator if target is set
                if let current = profile.currentWeightKg,
                   let target = Double(targetWeightKg),
                   target > 0 {
                    let diff = target - current
                    HStack(spacing: 8) {
                        Image(systemName: diff < 0 ? "arrow.down.circle.fill" : diff > 0 ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(diff == 0 ? .green : .accentColor)

                        Text(diff == 0 ? "You're at your target!" : String(format: "%+.1f kg from current weight", diff))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Activity Level", systemImage: "flame.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(UserProfile.ActivityLevel.allCases.enumerated()), id: \.element.id) { index, level in
                    ActivityLevelOption(
                        level: level,
                        isSelected: activityLevel == level,
                        index: index
                    ) {
                        activityLevel = level
                        HapticManager.lightTap()
                    }
                }
            }
        }
    }

    // MARK: - Plan Section

    private var planSection: some View {
        Button {
            showPlanAdjustment = true
            HapticManager.lightTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.body)
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
                    .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nutrition Plan")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("Adjust goals, calories & macros")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func saveChanges() {
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.heightCm = Double(heightCm)
        profile.targetWeightKg = targetWeightKg.isEmpty ? nil : Double(targetWeightKg)
        profile.activityLevelValue = activityLevel
        HapticManager.success()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: UserProfile.self, configurations: config)
    let profile = UserProfile()
    profile.name = "John"
    profile.heightCm = 175
    profile.currentWeightKg = 80
    profile.targetWeightKg = 75

    return ProfileEditSheet(profile: profile)
        .modelContainer(container)
}
