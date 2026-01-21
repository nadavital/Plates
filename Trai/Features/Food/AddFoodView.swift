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
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        if let imageData = selectedImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .clipShape(.rect(cornerRadius: 12))
                        } else {
                            ContentUnavailableView {
                                Label("Add Photo", systemImage: "camera.fill")
                            } description: {
                                Text("Take or select a photo of your food")
                            }
                            .frame(height: 150)
                        }
                    }
                    .onChange(of: selectedPhotoItem) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        }
                    }
                } header: {
                    Text("Photo")
                }

                // Description section
                Section {
                    TextField("Describe what you're eating...", text: $foodDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Describe your food for more accurate AI analysis")
                }

                // Meal type
                Section {
                    Picker("Meal", selection: $selectedMealType) {
                        ForEach(FoodEntry.MealType.allCases) { mealType in
                            Label(mealType.displayName, systemImage: mealType.iconName)
                                .tag(mealType)
                        }
                    }
                }

                // AI Analysis button
                Section {
                    Button {
                        Task {
                            await analyzeFood()
                        }
                    } label: {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                Text("Analyzing...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Analyze with AI", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedImageData == nil && foodDescription.isEmpty)
                    .disabled(isAnalyzing)
                }

                // Analysis result
                if let result = analysisResult {
                    Section {
                        LabeledContent("Food", value: result.name)
                        LabeledContent("Calories", value: "\(result.calories) kcal")
                        LabeledContent("Protein", value: "\(Int(result.proteinGrams))g")
                        LabeledContent("Carbs", value: "\(Int(result.carbsGrams))g")
                        LabeledContent("Fat", value: "\(Int(result.fatGrams))g")

                        if let serving = result.servingSize {
                            LabeledContent("Serving", value: serving)
                        }

                        if let notes = result.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            Text("Analysis Result")
                            Spacer()
                            Text(result.confidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button("Save Entry", systemImage: "checkmark.circle.fill") {
                            saveEntry()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // Manual entry toggle
                Section {
                    DisclosureGroup("Manual Entry", isExpanded: $showManualEntry) {
                        TextField("Food name", text: $manualName)
                        TextField("Calories", text: $manualCalories)
                            .keyboardType(.numberPad)
                        TextField("Protein (g)", text: $manualProtein)
                            .keyboardType(.decimalPad)
                        TextField("Carbs (g)", text: $manualCarbs)
                            .keyboardType(.decimalPad)
                        TextField("Fat (g)", text: $manualFat)
                            .keyboardType(.decimalPad)

                        Button("Save Manual Entry") {
                            saveManualEntry()
                        }
                        .disabled(manualName.isEmpty || manualCalories.isEmpty)
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func analyzeFood() async {
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

        entry.imageData = selectedImageData

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
