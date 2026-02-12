//
//  SettingsView.swift
//  Trai
//
//  App settings and preferences - all inline, no extra sheets
//

import SwiftUI

struct SettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var showPlanAdjustment = false
    @State private var showWorkoutPlanSetup = false
    @State private var showWorkoutPlanEdit = false
    @AppStorage("trai_coach_tone") private var coachToneRaw: String = TraiCoachTone.encouraging.rawValue

    var body: some View {
        List {
            // MARK: - Personal Info Section
            Section {
                // Name
                HStack {
                    Label("Name", systemImage: "person.fill")
                    Spacer()
                    TextField("Your name", text: $profile.name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.primary)
                }

                // Height
                HStack {
                    Label("Height", systemImage: "ruler")
                    Spacer()
                    TextField("cm", value: $profile.heightCm, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("cm")
                        .foregroundStyle(.secondary)
                }

                // Target Weight
                HStack {
                    Label("Target Weight", systemImage: "target")
                    Spacer()
                    TextField("—", value: $profile.targetWeightKg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text(profile.usesMetricWeight ? "kg" : "lbs")
                        .foregroundStyle(.secondary)
                }

                // Activity Level
                Picker(selection: Binding(
                    get: { profile.activityLevelValue },
                    set: { profile.activityLevelValue = $0 }
                )) {
                    ForEach(UserProfile.ActivityLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                } label: {
                    Label("Activity Level", systemImage: "flame.fill")
                }
            } header: {
                Text("Personal Info")
            }

            // MARK: - Trai Section
            Section {
                Picker(selection: coachToneBinding) {
                    ForEach(TraiCoachTone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                } label: {
                    Label("Coach Tone", systemImage: "circle.hexagongrid.circle")
                }
            } header: {
                Text("Trai")
            } footer: {
                Text("Pulse and Trai guidance will adapt to this tone while still learning from your behavior.")
            }

            // MARK: - Nutrition Plan Section
            Section {
                Button {
                    showPlanAdjustment = true
                } label: {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(.red)
                        Text("Adjust Nutrition Plan")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Adjust your daily calorie and macro targets.")
            }

            // MARK: - Workouts Section
            Section {
                Button {
                    if profile.hasWorkoutPlan {
                        showWorkoutPlanEdit = true
                    } else {
                        showWorkoutPlanSetup = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.red)
                        Text(profile.hasWorkoutPlan ? "Adjust Workout Plan" : "Create Workout Plan")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Picker(selection: Binding(
                    get: { profile.defaultWorkoutActionValue },
                    set: { profile.defaultWorkoutActionValue = $0 }
                )) {
                    ForEach(UserProfile.DefaultWorkoutAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                } label: {
                    Label("Quick Add Default", systemImage: "plus.circle.fill")
                }

                // Default rep count for new exercises
                Stepper(value: $profile.defaultRepCount, in: 1...30, step: 1) {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundStyle(.accent)
                        Text("Default Reps")
                        Spacer()
                        Text("\(profile.defaultRepCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Workouts")
            } footer: {
                if profile.defaultWorkoutActionValue == .recommendedWorkout && !profile.hasWorkoutPlan {
                    Text("Create a workout plan to use the recommended workout option.")
                } else {
                    Text("Default reps when adding new exercises. \(profile.defaultWorkoutActionValue.description)")
                }
            }

            // MARK: - Units Section
            Section {
                // Body weight units
                HStack {
                    Label("Body Weight", systemImage: "scalemass.fill")
                    Spacer()
                    Picker("Body Weight", selection: Binding(
                        get: { profile.usesMetricWeight },
                        set: {
                            profile.usesMetricWeight = $0
                            profile.usesMetricHeight = $0
                        }
                    )) {
                        Text("kg").tag(true)
                        Text("lbs").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }

                // Exercise weight units
                HStack {
                    Label("Exercise Weight", systemImage: "dumbbell.fill")
                    Spacer()
                    Picker("Exercise Weight", selection: $profile.usesMetricExerciseWeight) {
                        Text("kg").tag(true)
                        Text("lbs").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            } header: {
                Text("Units")
            }

            // MARK: - Macro Tracking Section
            Section {
                ForEach(MacroType.displayOrder) { macro in
                    MacroToggleRow(
                        macro: macro,
                        isEnabled: profile.enabledMacros.contains(macro)
                    ) {
                        if profile.enabledMacros.contains(macro) {
                            profile.enabledMacros.remove(macro)
                        } else {
                            profile.enabledMacros.insert(macro)
                        }
                    }
                }
            } header: {
                Text("Macro Tracking")
            } footer: {
                Text("Choose which nutrients to track. Disable all for calories only.")
            }

            // MARK: - Apple Health Section
            Section {
                Toggle(isOn: $profile.syncFoodToHealthKit) {
                    Label("Sync Food to Health", systemImage: "heart.fill")
                }

                Toggle(isOn: $profile.syncWeightToHealthKit) {
                    Label("Sync Weight to Health", systemImage: "scalemass.fill")
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Sync your food and weight data to Apple Health for a unified health view.")
            }

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPlanAdjustment) {
            PlanAdjustmentSheet(profile: profile)
        }
        .sheet(isPresented: $showWorkoutPlanSetup) {
            WorkoutPlanChatFlow()
        }
        .sheet(isPresented: $showWorkoutPlanEdit) {
            if let plan = profile.workoutPlan {
                WorkoutPlanEditSheet(currentPlan: plan)
            }
        }
    }

    private var coachToneBinding: Binding<TraiCoachTone> {
        Binding(
            get: { TraiCoachTone(rawValue: coachToneRaw) ?? .encouraging },
            set: { coachToneRaw = $0.rawValue }
        )
    }
}

// MARK: - Macro Toggle Row

private struct MacroToggleRow: View {
    let macro: MacroType
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isEnabled ? macro.color : macro.color.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: macro.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isEnabled ? .white : macro.color)
                    }

                Text(macro.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? macro.color : Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView(profile: UserProfile())
    }
}
