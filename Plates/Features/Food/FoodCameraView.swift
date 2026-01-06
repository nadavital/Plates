//
//  FoodCameraView.swift
//  Plates
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI

struct FoodCameraView: View {
    /// Session ID to add this food entry to (for grouping related entries)
    var sessionId: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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

    private var isReviewing: Bool {
        capturedImage != nil || isAnalyzingTextOnly
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera viewfinder - always present to stay "warm"
                CameraViewfinder(
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
                    ReviewCaptureView(
                        image: capturedImage,
                        description: $foodDescription,
                        isAnalyzing: isAnalyzing,
                        analysisResult: analysisResult,
                        errorMessage: errorMessage,
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

    private func goBackToCamera() {
        capturedImage = nil
        isAnalyzingTextOnly = false
        analysisResult = nil
        errorMessage = nil
    }

    private func submitTextDescription() {
        guard !foodDescription.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAnalyzingTextOnly = true
        // Auto-analyze when submitting text
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
        // Need either an image or a description
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

    private func saveEntry() {
        guard let result = analysisResult else { return }

        let entry = FoodEntry()
        entry.name = result.name
        entry.calories = result.calories
        entry.proteinGrams = result.proteinGrams
        entry.carbsGrams = result.carbsGrams
        entry.fatGrams = result.fatGrams
        entry.servingSize = result.servingSize
        entry.emoji = result.emoji
        entry.imageData = capturedImage?.jpegData(compressionQuality: 0.8)
        entry.userDescription = foodDescription
        entry.aiAnalysis = result.notes
        entry.inputMethod = capturedImage != nil ? "camera" : "description"

        // Assign session if adding to existing session
        if let sessionId {
            entry.sessionId = sessionId
            // Get next order number in session
            let existingCount = try? modelContext.fetchCount(
                FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
            )
            entry.sessionOrder = existingCount ?? 0
        }

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
        entry.servingSize = suggestion.servingSize
        entry.emoji = suggestion.emoji
        entry.imageData = capturedImage?.jpegData(compressionQuality: 0.8)
        entry.userDescription = foodDescription
        entry.aiAnalysis = "Refined from initial analysis"
        entry.inputMethod = capturedImage != nil ? "camera" : "description"

        // Assign session if adding to existing session
        if let sessionId {
            entry.sessionId = sessionId
            let existingCount = try? modelContext.fetchCount(
                FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
            )
            entry.sessionOrder = existingCount ?? 0
        }

        modelContext.insert(entry)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Camera Viewfinder

private struct CameraViewfinder: View {
    let cameraService: CameraService
    @Binding var description: String
    let onCapture: () -> Void
    let onManualEntry: () -> Void
    let onSubmitDescription: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    @FocusState private var isDescriptionFocused: Bool

    private var canSubmitDescription: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraService: cameraService)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture {
                    isDescriptionFocused = false
                }

            // Overlay gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            // Controls overlay
            VStack {
                Spacer()
                    .contentShape(.rect)
                    .onTapGesture {
                        isDescriptionFocused = false
                    }

                // Description input with send button
                HStack(spacing: 10) {
                    TextField("Describe your food...", text: $description)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                        .focused($isDescriptionFocused)
                        .onSubmit {
                            if canSubmitDescription {
                                onSubmitDescription()
                            }
                        }

                    if isDescriptionFocused {
                        if canSubmitDescription {
                            Button {
                                isDescriptionFocused = false
                                onSubmitDescription()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Button("Done") {
                                isDescriptionFocused = false
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)

                // Capture controls
                HStack(spacing: 32) {
                    // Photo library
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Library")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                    }

                    // Capture button
                    Button(action: onCapture) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }

                    // Manual entry
                    Button(action: onManualEntry) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                            Text("Manual")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Review Capture View

private struct ReviewCaptureView: View {
    let image: UIImage?
    @Binding var description: String
    let isAnalyzing: Bool
    let analysisResult: FoodAnalysis?
    let errorMessage: String?
    let onAnalyze: () -> Void
    let onSave: () -> Void
    let onSaveRefined: (SuggestedFoodEntry) -> Void

    @State private var isRefining = false
    @State private var refinementText = ""
    @State private var refinedSuggestion: SuggestedFoodEntry?
    @State private var isLoadingRefinement = false
    @State private var geminiService = GeminiService()
    @FocusState private var isRefinementFocused: Bool

    private var isTextOnly: Bool {
        image == nil
    }

    private var currentSuggestion: SuggestedFoodEntry? {
        if let refined = refinedSuggestion {
            return refined
        }
        guard let result = analysisResult else { return nil }
        return SuggestedFoodEntry(
            name: result.name,
            calories: result.calories,
            proteinGrams: result.proteinGrams,
            carbsGrams: result.carbsGrams,
            fatGrams: result.fatGrams,
            fiberGrams: result.fiberGrams,
            servingSize: result.servingSize,
            emoji: result.emoji
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Captured image or text-only indicator
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipShape(.rect(cornerRadius: 16))
                } else {
                    // Text-only mode header
                    VStack(spacing: 16) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.tint)

                        Text("Analyzing from description")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                }

                // Description input
                VStack(alignment: .leading, spacing: 8) {
                    Text(isTextOnly ? "Description" : "Description (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Add details about your food...", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 12))
                        .disabled(isTextOnly && analysisResult != nil) // Lock after analysis in text mode
                }

                // Analysis section - show meal card or error
                if let suggestion = currentSuggestion {
                    FoodSuggestionCard(
                        suggestion: suggestion,
                        isRefining: isRefining,
                        onSave: {
                            if refinedSuggestion != nil {
                                onSaveRefined(suggestion)
                            } else {
                                onSave()
                            }
                        },
                        onStartRefine: {
                            withAnimation(.spring(response: 0.3)) {
                                isRefining = true
                            }
                            isRefinementFocused = true
                        }
                    )
                } else if let error = errorMessage {
                    ErrorCard(message: error, onRetry: onAnalyze)
                }

                // Refinement chat interface
                if isRefining {
                    RefinementInputView(
                        text: $refinementText,
                        isLoading: isLoadingRefinement,
                        isFocused: $isRefinementFocused,
                        onSend: sendRefinement,
                        onCancel: {
                            withAnimation(.spring(response: 0.3)) {
                                isRefining = false
                                refinementText = ""
                            }
                        }
                    )
                }

                // Initial analyze button (before first analysis)
                if analysisResult == nil && errorMessage == nil {
                    Button(action: onAnalyze) {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Analyzing...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Label("Analyze with AI", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func sendRefinement() {
        guard !refinementText.trimmingCharacters(in: .whitespaces).isEmpty,
              let current = currentSuggestion else { return }

        isLoadingRefinement = true
        let correction = refinementText
        refinementText = ""

        Task {
            do {
                let imageData = image?.jpegData(compressionQuality: 0.8)
                let result = try await geminiService.refineFoodAnalysis(
                    correction: correction,
                    currentSuggestion: current,
                    imageData: imageData
                )

                withAnimation(.spring(response: 0.3)) {
                    refinedSuggestion = result
                    isRefining = false
                }
                HapticManager.success()
            } catch {
                HapticManager.error()
            }
            isLoadingRefinement = false
        }
    }
}

// MARK: - Food Suggestion Card

private struct FoodSuggestionCard: View {
    let suggestion: SuggestedFoodEntry
    let isRefining: Bool
    let onSave: () -> Void
    let onStartRefine: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text(suggestion.displayEmoji)
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()
            }

            // Meal name and calories
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.name)
                        .font(.headline)

                    if let servingSize = suggestion.servingSize {
                        Text(servingSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(suggestion.calories)")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Macros
            HStack(spacing: 12) {
                MacroPillView(label: "Protein", value: Int(suggestion.proteinGrams), color: .blue)
                MacroPillView(label: "Carbs", value: Int(suggestion.carbsGrams), color: .green)
                MacroPillView(label: "Fat", value: Int(suggestion.fatGrams), color: .yellow)
                if let fiber = suggestion.fiberGrams, fiber > 0 {
                    MacroPillView(label: "Fiber", value: Int(fiber), color: .brown)
                }
            }

            // Action buttons
            if !isRefining {
                HStack(spacing: 10) {
                    Button(action: onStartRefine) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.subheadline)
                            Text("Refine")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onSave) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Macro Pill View

private struct MacroPillView: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Refinement Input View

private struct RefinementInputView: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("What should I change?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel", action: onCancel)
                    .font(.subheadline)
            }

            HStack(spacing: 10) {
                TextField("e.g., \"It's actually a wrap\" or \"Add 100 more calories\"", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .focused(isFocused)

                Button {
                    onSend()
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Manual Food Entry Sheet

private struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let sessionId: UUID?
    let onSave: (FoodEntry) -> Void

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var servingSize = ""

    private var isValid: Bool {
        !name.isEmpty && Int(caloriesText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food name", text: $name)
                } header: {
                    Text("Name")
                }

                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calories")
                }

                Section {
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $proteinText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Macros")
                }

                Section {
                    TextField("e.g., 1 cup, 100g", text: $servingSize)
                } header: {
                    Text("Serving Size (optional)")
                }
            }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveEntry() {
        let entry = FoodEntry()
        entry.name = name
        entry.calories = Int(caloriesText) ?? 0
        entry.proteinGrams = Double(proteinText) ?? 0
        entry.carbsGrams = Double(carbsText) ?? 0
        entry.fatGrams = Double(fatText) ?? 0
        entry.servingSize = servingSize.isEmpty ? nil : servingSize
        entry.inputMethod = "manual"

        // Assign session if adding to existing session
        if let sessionId {
            entry.sessionId = sessionId
            // Get next order number in session
            let existingCount = try? modelContext.fetchCount(
                FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.sessionId == sessionId })
            )
            entry.sessionOrder = existingCount ?? 0
        }

        onSave(entry)
        dismiss()
    }
}

// MARK: - Analysis Result Card

private struct AnalysisResultCard: View {
    let result: FoodAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.displayEmoji)
                    .font(.title2)
                Text(result.name)
                    .font(.headline)
                Spacer()
                Text(result.confidence)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(.capsule)
            }

            Divider()

            HStack(spacing: 16) {
                NutritionValue(label: "Calories", value: "\(result.calories)", unit: "kcal")
                NutritionValue(label: "Protein", value: "\(Int(result.proteinGrams))", unit: "g")
                NutritionValue(label: "Carbs", value: "\(Int(result.carbsGrams))", unit: "g")
                NutritionValue(label: "Fat", value: "\(Int(result.fatGrams))", unit: "g")
            }

            if let serving = result.servingSize {
                Text("Serving: \(serving)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = result.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct NutritionValue: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .bold()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Error Card

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.cameraService = cameraService
        cameraService.setupPreviewLayer(in: view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Ensure preview layer frame is updated when view appears/resizes
        uiView.updatePreviewFrame()
    }
}

/// Custom UIView that updates preview layer frame on layout
class CameraPreviewUIView: UIView {
    weak var cameraService: CameraService?

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewFrame()
    }

    func updatePreviewFrame() {
        // Update all sublayers to match current bounds
        layer.sublayers?.forEach { sublayer in
            if sublayer is AVCaptureVideoPreviewLayer {
                sublayer.frame = bounds
            }
        }
    }
}

// MARK: - Camera Service

@Observable
@MainActor
final class CameraService: NSObject {
    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    var isAuthorized = false

    func requestPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            isAuthorized = true
            await setupCamera()
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            if isAuthorized {
                await setupCamera()
            }
        default:
            isAuthorized = false
        }
    }

    private func setupCamera() async {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        Task.detached { [captureSession] in
            captureSession.startRunning()
        }
    }

    func setupPreviewLayer(in view: UIView) {
        // Remove existing preview layer if any
        previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.connection?.videoOrientation = .portrait

        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                photoContinuation?.resume(returning: nil)
                photoContinuation = nil
                return
            }

            photoContinuation?.resume(returning: image)
            photoContinuation = nil
        }
    }
}

#Preview {
    FoodCameraView()
}
