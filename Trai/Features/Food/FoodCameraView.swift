//
//  FoodCameraView.swift
//  Trai
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData
import PhotosUI

@MainActor
final class FoodCameraPresentation: Identifiable {
    let id = UUID()
    let sessionId: UUID?
    let targetDate: Date?

    init(sessionId: UUID? = nil, targetDate: Date? = nil) {
        self.sessionId = sessionId
        self.targetDate = targetDate
    }
}

struct FoodCameraView: View {
    /// Session ID to add this food entry to (for grouping related entries)
    var sessionId: UUID?
    var targetDate: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @Query private var profiles: [UserProfile]

    @State private var draft: FoodLogDraft?
    @State private var showingManualEntry = false
    @State private var pendingManualEntry: FoodEntry?

    private var enabledMacros: Set<MacroType> {
        profiles.first?.enabledMacros ?? MacroType.defaultEnabled
    }

    private var canAccessFoodAI: Bool {
        monetizationService?.canAccessAIFeatures ?? true
    }

    private var requiresAuthenticatedAccountForFoodAI: Bool {
        accountSessionService?.isAuthenticated != true
    }

    var body: some View {
        Group {
            if !canAccessFoodAI {
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else if requiresAuthenticatedAccountForFoodAI {
                AccountSetupView(context: .aiFeatures)
            } else {
                NavigationStack {
                    if draft == nil {
                        FoodLogCaptureStepView(
                            sessionId: sessionId,
                            onDraftReady: { draft in
                                self.draft = draft
                            },
                            onManualEntryRequested: { showingManualEntry = true },
                            onCancel: { dismiss() }
                        )
                    } else {
                        FoodLogReviewStepView(
                            draft: draftBinding,
                            enabledMacros: enabledMacros,
                            onRetake: { draft = nil },
                            onFinish: { dismiss() },
                            targetDate: targetDate
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodEntrySheet(sessionId: sessionId, targetDate: targetDate) { entry in
                pendingManualEntry = entry
                showingManualEntry = false
            }
            .traiSheetBranding()
        }
        .onChange(of: showingManualEntry) { _, isShowing in
            guard !isShowing else { return }

            if let pendingManualEntry {
                self.pendingManualEntry = nil
                saveManualEntry(pendingManualEntry)
            } else if !canAccessFoodAI {
                dismiss()
            }
        }
        .task(id: canAccessFoodAI) {
            if !canAccessFoodAI && !showingManualEntry {
                showingManualEntry = true
            }
        }
        .tint(TraiColors.brandAccent)
        .accentColor(TraiColors.brandAccent)
        .proUpsellPresenter()
    }

    private var draftBinding: Binding<FoodLogDraft> {
        Binding(
            get: { draft ?? FoodLogDraft(sessionId: sessionId, inputSource: .description) },
            set: { draft = $0 }
        )
    }

    private func saveManualEntry(_ entry: FoodEntry) {
        modelContext.insert(entry)
        WidgetDataProvider.shared.updateWidgetData(modelContext: modelContext)
        recordFoodLogBehavior(entry: entry, source: "manual_entry", modelContext: modelContext)
        saveFoodMacrosToHealthKit(entry, healthKitService: healthKitService)
        HapticManager.success()
        dismiss()
    }
}

private struct FoodLogCaptureStepView: View {
    let sessionId: UUID?
    let onDraftReady: (FoodLogDraft) -> Void
    let onManualEntryRequested: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var cameraService = CameraService()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var foodDescription = ""
    @State private var isCapturingPhoto = false
    @State private var showingCameraPermissionAlert = false

    var body: some View {
        FoodCameraViewfinder(
            cameraService: cameraService,
            isCapturingPhoto: isCapturingPhoto,
            description: $foodDescription,
            onCapture: capturePhoto,
            onManualEntry: onManualEntryRequested,
            onSubmitDescription: submitTextDescription,
            selectedPhotoItem: $selectedPhotoItem
        )
        .overlay(alignment: .topLeading) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("foodCameraCaptureReady")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    onCancel()
                }
                .foregroundStyle(.white)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task { @MainActor in
                guard let data = try? await newValue?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    return
                }

                onDraftReady(
                    FoodLogDraft(
                        sessionId: sessionId,
                        image: image,
                        description: trimmedDescription,
                        inputSource: .photo
                    )
                )
                selectedPhotoItem = nil
            }
        }
        .task {
            guard !AppLaunchArguments.isUITesting else { return }
            await cameraService.requestPermission()
            if !cameraService.isAuthorized {
                showingCameraPermissionAlert = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !AppLaunchArguments.isUITesting else { return }
            Task { @MainActor in
                guard !cameraService.isAuthorized else { return }
                await cameraService.requestPermission()
                if cameraService.isAuthorized {
                    showingCameraPermissionAlert = false
                }
            }
        }
        .alert("Camera Access Needed", isPresented: $showingCameraPermissionAlert) {
            Button("Open Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
            Button("Cancel", role: .cancel) {
                onCancel()
            }
        } message: {
            Text("Allow camera access in Settings to log food with a photo.")
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }

    private var trimmedDescription: String {
        foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capturePhoto() {
        guard !isCapturingPhoto else { return }

        Task { @MainActor in
            isCapturingPhoto = true
            defer { isCapturingPhoto = false }

            guard let image = await cameraService.capturePhoto() else { return }
            HapticManager.mediumTap()
            onDraftReady(
                FoodLogDraft(
                    sessionId: sessionId,
                    image: image,
                    description: trimmedDescription,
                    inputSource: .camera
                )
            )
        }
    }

    private func submitTextDescription() {
        guard !trimmedDescription.isEmpty else { return }
        onDraftReady(
            FoodLogDraft(
                sessionId: sessionId,
                image: nil,
                description: trimmedDescription,
                inputSource: .description
            )
        )
    }
}

private struct FoodLogReviewStepView: View {
    @Binding var draft: FoodLogDraft
    let enabledMacros: Set<MacroType>
    let onRetake: () -> Void
    let onFinish: () -> Void
    var targetDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?

    @State private var aiService = AIService()
    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String?
    @State private var isLoadingRefinement = false
    @State private var refinementErrorMessage: String?

    var body: some View {
        FoodCameraReviewView(
            image: draft.image,
            description: $draft.description,
            isAnalyzing: isAnalyzing,
            analysisResult: draft.analysisResult,
            refinedSuggestion: draft.refinedSuggestion,
            errorMessage: analysisErrorMessage,
            refinementErrorMessage: refinementErrorMessage,
            enabledMacros: enabledMacros,
            isLoadingRefinement: isLoadingRefinement,
            onAnalyze: analyzeFood,
            onSave: saveEntry,
            onRefine: refineFood
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onRetake()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Retake")
                    }
                }
                .disabled(isAnalyzing || isLoadingRefinement)
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: autoAnalyzeKey) {
            guard shouldAutoAnalyzeDescription else { return }
            analyzeFood()
        }
    }

    private var autoAnalyzeKey: String {
        "\(draft.inputSource.rawValue)|\(draft.description)|\(draft.analysisResult == nil)"
    }

    private var shouldAutoAnalyzeDescription: Bool {
        draft.inputSource == .description &&
        draft.analysisResult == nil &&
        !trimmedDescription.isEmpty &&
        !isAnalyzing
    }

    private var trimmedDescription: String {
        draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSuggestion: SuggestedFoodEntry? {
        if let refinedSuggestion = draft.refinedSuggestion {
            return refinedSuggestion
        }

        guard let analysisResult = draft.analysisResult else { return nil }
        return SuggestedFoodEntry(
            name: analysisResult.name,
            calories: analysisResult.calories,
            proteinGrams: analysisResult.proteinGrams,
            carbsGrams: analysisResult.carbsGrams,
            fatGrams: analysisResult.fatGrams,
            fiberGrams: analysisResult.fiberGrams,
            sugarGrams: analysisResult.sugarGrams,
            servingSize: analysisResult.servingSize,
            emoji: analysisResult.emoji
        )
    }

    private func analyzeFood() {
        guard !isAnalyzing else { return }
        guard draft.image != nil || !trimmedDescription.isEmpty else { return }
        guard monetizationService?.canAccessAIFeatures ?? true else {
            proUpsellCoordinator?.present(source: .foodAnalysis)
            return
        }

        isAnalyzing = true
        analysisErrorMessage = nil
        refinementErrorMessage = nil
        draft.refinedSuggestion = nil

        Task { @MainActor in
            defer { isAnalyzing = false }

            do {
                let result = try await aiService.analyzeFoodImage(
                    draft.image?.jpegData(compressionQuality: 0.8),
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription
                )
                draft.analysisResult = result
                HapticManager.success()
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticManager.error()
            }
        }
    }

    private func refineFood(_ correction: String) {
        guard !isLoadingRefinement, let currentSuggestion else { return }
        guard monetizationService?.canAccessAIFeatures ?? true else {
            proUpsellCoordinator?.present(source: .foodAnalysis)
            return
        }

        isLoadingRefinement = true
        refinementErrorMessage = nil

        Task { @MainActor in
            defer { isLoadingRefinement = false }

            do {
                let refinedSuggestion = try await aiService.refineFoodAnalysis(
                    correction: correction,
                    currentSuggestion: currentSuggestion,
                    imageData: draft.image?.jpegData(compressionQuality: 0.8)
                )
                draft.refinedSuggestion = refinedSuggestion
                HapticManager.success()
            } catch {
                refinementErrorMessage = error.localizedDescription
                HapticManager.error()
            }
        }
    }

    private func saveEntry(_ suggestion: SuggestedFoodEntry, isRefined: Bool) {
        let entry = FoodEntry()
        entry.name = suggestion.name
        entry.calories = suggestion.calories
        entry.proteinGrams = suggestion.proteinGrams
        entry.carbsGrams = suggestion.carbsGrams
        entry.fatGrams = suggestion.fatGrams
        entry.fiberGrams = suggestion.fiberGrams
        entry.sugarGrams = suggestion.sugarGrams
        entry.servingSize = suggestion.servingSize
        entry.emoji = FoodEmojiResolver.resolve(preferred: suggestion.emoji, foodName: suggestion.name)
        entry.imageData = draft.image?.jpegData(compressionQuality: 0.8)
        entry.userDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
        entry.aiAnalysis = isRefined ? "Refined from initial analysis" : draft.analysisResult?.notes
        entry.input = draft.inputSource.foodEntryInputMethod
        entry.loggedAt = resolvedFoodLogDate(targetDate: targetDate, sessionId: draft.sessionId, modelContext: modelContext)
        entry.ensureDisplayMetadata()

        assignFoodSession(draft.sessionId, to: entry, modelContext: modelContext)
        modelContext.insert(entry)
        WidgetDataProvider.shared.updateWidgetData(modelContext: modelContext)

        let behaviorSource = isRefined
            ? "refined_\(draft.inputSource.behaviorSource)"
            : draft.inputSource.behaviorSource
        recordFoodLogBehavior(entry: entry, source: behaviorSource, modelContext: modelContext)
        saveFoodMacrosToHealthKit(entry, healthKitService: healthKitService)

        HapticManager.success()
        onFinish()
    }
}

private func assignFoodSession(_ sessionId: UUID?, to entry: FoodEntry, modelContext: ModelContext) {
    guard let sessionId else { return }
    entry.sessionId = sessionId
    let existingCount = try? modelContext.fetchCount(
        FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
    )
    entry.sessionOrder = existingCount ?? 0
}

func resolvedFoodLogDate(targetDate: Date?, sessionId: UUID?, modelContext: ModelContext) -> Date {
    if let sessionId {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\FoodEntry.sessionOrder)]
        )

        if let sessionDate = try? modelContext.fetch(descriptor).first?.loggedAt {
            return sessionDate
        }
    }

    guard let targetDate else { return Date() }
    return combineDay(targetDate, withTimeFrom: Date())
}

private func combineDay(_ day: Date, withTimeFrom timeSource: Date) -> Date {
    let calendar = Calendar.current
    var dateComponents = calendar.dateComponents([.year, .month, .day], from: day)
    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
    dateComponents.hour = timeComponents.hour
    dateComponents.minute = timeComponents.minute
    dateComponents.second = timeComponents.second
    return calendar.date(from: dateComponents) ?? day
}

private func saveFoodMacrosToHealthKit(_ entry: FoodEntry, healthKitService: HealthKitService?) {
    guard let healthKitService else { return }
    Task {
        do {
            try await healthKitService.saveFoodMacros(
                calories: entry.calories,
                proteinGrams: entry.proteinGrams,
                carbsGrams: entry.carbsGrams,
                fatGrams: entry.fatGrams,
                fiberGrams: entry.fiberGrams,
                sugarGrams: entry.sugarGrams,
                date: entry.loggedAt
            )
        } catch {
            print("Failed to save macros to HealthKit: \(error)")
        }
    }
}

private func recordFoodLogBehavior(entry: FoodEntry, source: String, modelContext: ModelContext) {
    BehaviorTracker(modelContext: modelContext).record(
        actionKey: BehaviorActionKey.logFood,
        domain: .nutrition,
        surface: .food,
        outcome: .completed,
        relatedEntityId: entry.id,
        metadata: [
            "source": source,
            "name": entry.name
        ]
    )
}
