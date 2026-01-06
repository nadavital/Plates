//
//  FoodCameraView.swift
//  Plates
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct FoodCameraView: View {
    /// Session ID to add this food entry to (for grouping related entries)
    var sessionId: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var cameraService = CameraService()
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var foodDescription = ""
    @State private var isAnalyzing = false
    @State private var analysisResult: FoodAnalysis?
    @State private var errorMessage: String?
    @State private var geminiService = GeminiService()
    @State private var showingManualEntry = false

    /// True when reviewing a captured image OR analyzing a text description
    @State private var isAnalyzingTextOnly = false

    private var profile: UserProfile? { profiles.first }

    private var isReviewing: Bool {
        capturedImage != nil || isAnalyzingTextOnly
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera viewfinder - always present to stay "warm"
                FoodCameraViewfinder(
                    cameraService: cameraService,
                    description: $foodDescription,
                    onCapture: capturePhoto,
                    onManualEntry: { showingManualEntry = true },
                    onSubmitDescription: submitTextDescription,
                    selectedPhotoItem: $selectedPhotoItem
                )
                .opacity(isReviewing ? 0 : 1)

                // Review captured image or text description
                if isReviewing {
                    FoodCameraReviewView(
                        image: capturedImage,
                        description: $foodDescription,
                        isAnalyzing: isAnalyzing,
                        analysisResult: analysisResult,
                        errorMessage: errorMessage,
                        enabledMacros: profile?.enabledMacros ?? MacroType.defaultEnabled,
                        onAnalyze: analyzeFood,
                        onSave: saveEntry,
                        onSaveRefined: saveRefinedEntry
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isReviewing {
                        Button {
                            goBackToCamera()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Retake")
                            }
                        }
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(isReviewing ? .visible : .hidden, for: .navigationBar)
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        capturedImage = uiImage
                    }
                }
            }
            .task {
                await cameraService.requestPermission()
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualFoodEntrySheet(sessionId: sessionId, onSave: { entry in
                    modelContext.insert(entry)
                    HapticManager.success()
                    dismiss()
                })
            }
        }
    }

    // MARK: - Actions

    private func goBackToCamera() {
        capturedImage = nil
        isAnalyzingTextOnly = false
        analysisResult = nil
        errorMessage = nil
    }

    private func submitTextDescription() {
        guard !foodDescription.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAnalyzingTextOnly = true
        analyzeFood()
    }

    private func capturePhoto() {
        Task {
            if let image = await cameraService.capturePhoto() {
                HapticManager.mediumTap()
                capturedImage = image
            }
        }
    }

    private func analyzeFood() {
        guard capturedImage != nil || !foodDescription.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil

        Task {
            do {
                let imageData = capturedImage?.jpegData(compressionQuality: 0.8)
                let result = try await geminiService.analyzeFoodImage(
                    imageData,
                    description: foodDescription.isEmpty ? nil : foodDescription
                )
                analysisResult = result
                HapticManager.success()
            } catch {
                errorMessage = error.localizedDescription
                HapticManager.error()
            }
            isAnalyzing = false
        }
    }

    // MARK: - Save Methods

    private func saveEntry() {
        guard let result = analysisResult else { return }

        let entry = FoodEntry()
        entry.name = result.name
        entry.calories = result.calories
        entry.proteinGrams = result.proteinGrams
        entry.carbsGrams = result.carbsGrams
        entry.fatGrams = result.fatGrams
        entry.fiberGrams = result.fiberGrams
        entry.sugarGrams = result.sugarGrams
        entry.servingSize = result.servingSize
        entry.emoji = result.emoji
        entry.imageData = capturedImage?.jpegData(compressionQuality: 0.8)
        entry.userDescription = foodDescription
        entry.aiAnalysis = result.notes
        entry.inputMethod = capturedImage != nil ? "camera" : "description"

        assignSession(to: entry)
        modelContext.insert(entry)
        HapticManager.success()
        dismiss()
    }

    private func saveRefinedEntry(_ suggestion: SuggestedFoodEntry) {
        let entry = FoodEntry()
        entry.name = suggestion.name
        entry.calories = suggestion.calories
        entry.proteinGrams = suggestion.proteinGrams
        entry.carbsGrams = suggestion.carbsGrams
        entry.fatGrams = suggestion.fatGrams
        entry.fiberGrams = suggestion.fiberGrams
        entry.sugarGrams = suggestion.sugarGrams
        entry.servingSize = suggestion.servingSize
        entry.emoji = suggestion.emoji
        entry.imageData = capturedImage?.jpegData(compressionQuality: 0.8)
        entry.userDescription = foodDescription
        entry.aiAnalysis = "Refined from initial analysis"
        entry.inputMethod = capturedImage != nil ? "camera" : "description"

        assignSession(to: entry)
        modelContext.insert(entry)
        HapticManager.success()
        dismiss()
    }

    private func assignSession(to entry: FoodEntry) {
        guard let sessionId else { return }
        entry.sessionId = sessionId
        let existingCount = try? modelContext.fetchCount(
            FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
        )
        entry.sessionOrder = existingCount ?? 0
    }
}

#Preview {
    FoodCameraView()
}
