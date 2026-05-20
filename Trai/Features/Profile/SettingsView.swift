//
//  SettingsView.swift
//  Trai
//
//  App settings and preferences - all inline, no extra sheets
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(AppAccountService.self) private var appAccountService: AppAccountService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @State private var showPlanAdjustment = false
    @State private var showWorkoutPlanSetup = false
    @State private var showWorkoutPlanEdit = false
    @State private var standardWorkoutPlanDraft = OnboardingWorkoutPlanDraft()
    @State private var standardWorkoutPlanAIService = AIService()
    @State private var pendingEnabledMacroReveal: MacroType?
    @State private var presentedAccountSetupContext: AccountSetupContext?
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var accountActionError: AccountActionError?
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
                        .frame(minWidth: 60, idealWidth: 72, maxWidth: 96)
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
                        .frame(minWidth: 60, idealWidth: 72, maxWidth: 96)
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
                Text("Trai guidance will adapt to this tone while still learning from your behavior.")
            }

            if let accountSessionService {
                Section {
                    if accountSessionService.isAuthenticated {
                        LabeledContent {
                            Text(accountSessionService.currentUserDisplayName)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Signed In", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        Button {
                            accountSessionService.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        Button(role: .destructive) {
                            isShowingDeleteAccountConfirmation = true
                        } label: {
                            Label(
                                accountSessionService.isSyncingAccount ? "Deleting Account..." : "Delete Account",
                                systemImage: "person.crop.circle.badge.xmark"
                            )
                        }
                        .disabled(accountSessionService.isSyncingAccount)
                    } else {
                        Button {
                            if let recommendedEnvironment = appAccountService?.recommendedBackendEnvironmentForRealAccountSignIn {
                                appAccountService?.setBackendEnvironment(recommendedEnvironment)
                            }
                            presentedAccountSetupContext = .secureExistingData
                        } label: {
                            Label("Set Up Account", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Deleting your account removes Trai backend account data and signs you out on this device. App Store subscriptions remain managed by Apple.")
                }
            }

#if DEBUG
            Section {
                NavigationLink {
                    DeveloperSettingsView()
                } label: {
                    Label("Developer Settings", systemImage: "hammer")
                }
            } footer: {
                Text("Backend, billing, account, and testing controls live here while the app is still in local development.")
            }
#endif

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

                Picker(selection: Binding(
                    get: { profile.volumePRModeValue },
                    set: { profile.volumePRModeValue = $0 }
                )) {
                    ForEach(UserProfile.VolumePRMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label("Volume PR Mode", systemImage: "chart.bar.xaxis")
                }
            } header: {
                Text("Workouts")
            } footer: {
                if profile.defaultWorkoutActionValue == .recommendedWorkout && !profile.hasWorkoutPlan {
                    Text("Create a workout plan to use the recommended workout option.")
                } else {
                    Text("Default reps when adding new exercises. \(profile.defaultWorkoutActionValue.description) Volume PR mode: \(profile.volumePRModeValue.description).")
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
                    .frame(minWidth: 110, idealWidth: 128, maxWidth: 160)
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
                    .frame(minWidth: 110, idealWidth: 128, maxWidth: 160)
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
                            pendingEnabledMacroReveal = macro
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
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showPlanAdjustment) {
            PlanAdjustmentSheet(profile: profile)
                .traiSheetBranding()
        }
        .sheet(item: $presentedAccountSetupContext) { context in
            AccountSetupView(context: context)
                .traiSheetBranding()
        }
        .confirmationDialog(
            "Delete Trai Account?",
            isPresented: $isShowingDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your Trai backend account data and signs you out. It does not cancel App Store subscriptions.")
        }
        .alert(item: $accountActionError) { error in
            Alert(
                title: Text("Account Action Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $pendingEnabledMacroReveal) { macro in
            Alert(
                title: Text("\(macro.displayName) target ready"),
                message: Text("\(profile.goalFor(macro))g per day is already saved in your Trai plan for \(macro.displayName.lowercased()). Keep it, or review your plan if you want to change it."),
                primaryButton: .default(Text("Review Plan")) {
                    showPlanAdjustment = true
                },
                secondaryButton: .cancel(Text("Keep Target"))
            )
        }
        .sheet(isPresented: $showWorkoutPlanSetup) {
            WorkoutPlanSetupChoiceFlow(
                draft: $standardWorkoutPlanDraft,
                context: standardWorkoutPlanSetupContext,
                aiService: standardWorkoutPlanAIService,
                canAccessAIFeatures: monetizationService?.canAccessAIFeatures ?? true,
                onComplete: saveStandardWorkoutPlan,
                onBack: { showWorkoutPlanSetup = false }
            )
                .traiSheetBranding()
        }
        .sheet(isPresented: $showWorkoutPlanEdit) {
            if let plan = profile.workoutPlan {
                WorkoutPlanEditSheet(currentPlan: plan)
                    .traiSheetBranding()
            }
        }
    }

    private var coachToneBinding: Binding<TraiCoachTone> {
        Binding(
            get: { TraiCoachTone(rawValue: coachToneRaw) ?? .encouraging },
            set: { coachToneRaw = $0.rawValue }
        )
    }

    private func deleteAccount() {
        guard let accountSessionService else { return }
        Task {
            do {
                try await accountSessionService.deleteAccount()
            } catch {
                accountActionError = AccountActionError(message: error.localizedDescription)
            }
        }
    }

    private var standardWorkoutPlanSetupContext: OnboardingWorkoutPlanUserContext {
        OnboardingWorkoutPlanUserContext(
            name: profile.name,
            age: profile.age ?? 30,
            gender: profile.genderValue,
            goal: profile.goal,
            activityLevel: profile.activityLevelValue,
            nutritionContext: OnboardingWorkoutPlanUserContext.nutritionContext(from: profile),
            memoryContext: workoutPlanMemoryContext(),
            activeWorkoutGoalContext: OnboardingWorkoutPlanUserContext.activeGoalContext(from: activeWorkoutGoalsForPlanSetup())
        )
    }

    private func saveStandardWorkoutPlan(
        _ plan: WorkoutPlan,
        generatedGoals: [WorkoutGoal],
        mode: WorkoutPlanSetupMode,
        draftSnapshot: OnboardingWorkoutPlanDraft
    ) {
        let hadExistingPlan = profile.workoutPlan != nil

        WorkoutPlanHistoryService.archiveCurrentPlanIfExists(
            profile: profile,
            reason: .chatAdjustment,
            modelContext: modelContext,
            replacingWith: plan
        )

        profile.workoutPlan = plan
        draftSnapshot.applyPreferences(to: profile, generatedPlan: plan)

        if mode == .proAI {
            insertGeneratedWorkoutGoals(generatedGoals)
        }

        if !hadExistingPlan {
            WorkoutPlanHistoryService.archivePlan(
                plan,
                profile: profile,
                reason: .chatCreate,
                modelContext: modelContext
            )
        }

        try? modelContext.save()
        standardWorkoutPlanDraft = OnboardingWorkoutPlanDraft()
        showWorkoutPlanSetup = false
        HapticManager.success()
    }

    private func workoutPlanMemoryContext() -> [String] {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate<CoachMemory> { memory in
                memory.isActive
            },
            sortBy: [
                SortDescriptor(\CoachMemory.importance, order: .reverse),
                SortDescriptor(\CoachMemory.createdAt, order: .reverse)
            ]
        )
        let memories = (try? modelContext.fetch(descriptor)) ?? []
        return memories
            .filter {
                $0.topic == .workout || $0.topic == .general || $0.category == .goal || $0.category == .context || $0.category == .restriction
            }
            .prefix(8)
            .map(\.promptFormat)
    }

    private func activeWorkoutGoalsForPlanSetup() -> [WorkoutGoal] {
        let descriptor = FetchDescriptor<WorkoutGoal>(
            predicate: #Predicate<WorkoutGoal> { goal in
                goal.statusRaw == "active"
            },
            sortBy: [SortDescriptor(\WorkoutGoal.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func insertGeneratedWorkoutGoals(_ goals: [WorkoutGoal]) {
        var existingTitles = Set(activeWorkoutGoalsForPlanSetup().map { $0.trimmedTitle.lowercased() })
        for goal in goals {
            let titleKey = goal.trimmedTitle.lowercased()
            guard !titleKey.isEmpty, !existingTitles.contains(titleKey) else { continue }
            modelContext.insert(goal)
            existingTitles.insert(titleKey)
        }
    }

}

private struct AccountActionError: Identifiable {
    let id = UUID()
    let message: String
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
