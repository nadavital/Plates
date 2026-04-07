//
//  AddFoodView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddFoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?

    @State private var geminiService = GeminiService()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var foodDescription = ""
    @State private var selectedMealType: FoodEntry.MealType = .snack
    @State private var isAnalyzing = false
    @State private var analysisResult: FoodAnalysis?
    @State private var errorMessage: String?

    // Manual entry fields
    @State private var showManualEntry = false
    @State private var manualName = ""
    @State private var manualServingSize = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    photoSection
                        .traiCard(cornerRadius: 16)

                    descriptionSection
                        .traiCard(cornerRadius: 16)

                    mealTypeSection
                        .traiCard(cornerRadius: 16)

                    analyzeSection
                        .traiCard(cornerRadius: 16)

                    if let result = analysisResult {
                        analysisSection(result)
                            .traiCard(cornerRadius: 16)
                    }

                    if let error = errorMessage {
                        errorSection(error)
                            .traiCard(cornerRadius: 16)
                    }

                    manualEntrySection
                        .traiCard(cornerRadius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Photo", icon: "camera.fill")

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Group {
                    if let imageData = selectedImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipShape(.rect(cornerRadius: 12))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text("Select food photo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Take or choose a clear image for better analysis")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Description", icon: "text.alignleft")

            TextField("Describe what you're eating...", text: $foodDescription, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Text("Describe your food for more accurate AI analysis")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mealTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Meal", icon: "clock")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FoodEntry.MealType.allCases) { mealType in
                    if selectedMealType == mealType {
                        Button {
                            selectedMealType = mealType
                            HapticManager.lightTap()
                        } label: {
                            Label(mealType.displayName, systemImage: mealType.iconName)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.traiSecondary(color: .accentColor, fullWidth: true))
                    } else {
                        Button {
                            selectedMealType = mealType
                            HapticManager.lightTap()
                        } label: {
                            Label(mealType.displayName, systemImage: mealType.iconName)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.traiTertiary(color: .secondary, fullWidth: true))
                    }
                }
            }
        }
    }

    private var analyzeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("AI Analysis", icon: "sparkles")

            Button {
                Task {
                    await analyzeFood()
                }
            } label: {
                HStack(spacing: 8) {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Analyzing..." : "Analyze with AI")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiPrimary(fullWidth: true))
            .disabled((selectedImageData == nil && foodDescription.isEmpty) || isAnalyzing)
        }
    }

    private func analysisSection(_ result: FoodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Analysis Result", icon: "checkmark.seal.fill")
                Spacer()
                Text(result.confidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                infoRow(label: "Food", value: result.name)
                infoRow(label: "Calories", value: "\(result.calories) kcal")
                infoRow(label: "Protein", value: "\(Int(result.proteinGrams))g")
                infoRow(label: "Carbs", value: "\(Int(result.carbsGrams))g")
                infoRow(label: "Fat", value: "\(Int(result.fatGrams))g")

                if let serving = result.servingSize {
                    infoRow(label: "Serving", value: serving)
                }
            }

            if let notes = result.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Button("Save Entry", systemImage: "checkmark.circle.fill") {
                saveEntry()
            }
            .buttonStyle(.traiPrimary(fullWidth: true))
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Error", icon: "exclamationmark.triangle.fill")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    showManualEntry.toggle()
                }
            } label: {
                HStack {
                    Label("Manual Entry", systemImage: "square.and.pencil")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showManualEntry ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showManualEntry {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Food Details", systemImage: "fork.knife")
                            .font(.traiHeadline())
                            .foregroundStyle(.primary)

                        Text("Name and quantity")
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)

                        TextField("e.g. Grilled chicken salad", text: $manualName)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quantity")
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)

                        TextField("e.g. 1 bowl, 150 g, 2 slices", text: $manualServingSize)
                            .textContentType(.none)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calories")
                            .font(.traiLabel(12))
                            .foregroundStyle(.secondary)

                        TextField("e.g. 450", text: $manualCalories)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(spacing: 8) {
                        nutrientField("Protein (g)", text: $manualProtein)
                        nutrientField("Carbs (g)", text: $manualCarbs)
                    }

                    nutrientField("Fat (g)", text: $manualFat)

                    Button("Save Manual Entry", systemImage: "checkmark") {
                        saveManualEntry()
                    }
                    .buttonStyle(.traiPrimary(fullWidth: true))
                    .disabled(manualName.isEmpty || manualCalories.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func nutrientField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .padding(12)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func analyzeFood() async {
        if !(monetizationService?.canAccessAIFeatures ?? true) {
            proUpsellCoordinator?.present(source: .foodAnalysis)
            return
        }

        isAnalyzing = true
        errorMessage = nil

        do {
            let result = try await geminiService.analyzeFoodImage(
                selectedImageData,
                description: foodDescription.isEmpty ? nil : foodDescription
            )
            analysisResult = result
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func saveEntry() {
        guard let result = analysisResult else { return }

        let entry = FoodEntry(
            name: result.name,
            mealType: selectedMealType.rawValue,
            calories: result.calories,
            proteinGrams: result.proteinGrams,
            carbsGrams: result.carbsGrams,
            fatGrams: result.fatGrams
        )

        entry.servingSize = result.servingSize
        entry.imageData = selectedImageData
        entry.userDescription = foodDescription
        entry.aiAnalysis = result.notes
        entry.emoji = FoodEmojiResolver.resolve(preferred: result.emoji, foodName: result.name)
        entry.ensureDisplayMetadata()

        modelContext.insert(entry)
        saveMacrosToHealthKit(entry)
        dismiss()
    }

    private func saveManualEntry() {
        guard !manualName.isEmpty,
              let calories = Int(manualCalories) else { return }

        let entry = FoodEntry(
            name: manualName,
            mealType: selectedMealType.rawValue,
            calories: calories,
            proteinGrams: Double(manualProtein) ?? 0,
            carbsGrams: Double(manualCarbs) ?? 0,
            fatGrams: Double(manualFat) ?? 0
        )

        entry.servingSize = manualServingSize.isEmpty ? nil : manualServingSize
        entry.imageData = selectedImageData
        entry.emoji = FoodEmojiResolver.resolve(preferred: nil, foodName: manualName)
        entry.ensureDisplayMetadata()

        modelContext.insert(entry)
        saveMacrosToHealthKit(entry)
        dismiss()
    }

    private func saveMacrosToHealthKit(_ entry: FoodEntry) {
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
}

#Preview {
    AddFoodView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
