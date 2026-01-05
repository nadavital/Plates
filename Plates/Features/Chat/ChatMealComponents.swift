//
//  ChatMealComponents.swift
//  Plates
//
//  Meal suggestion and logging UI components for chat
//

import SwiftUI

// MARK: - Logged Meal Badge

struct LoggedMealBadge: View {
    let meal: SuggestedFoodEntry?
    let foodEntryId: UUID?
    let onTap: () -> Void

    private var displayText: String {
        if let name = meal?.name {
            return "Logged \(name)"
        }
        return "Meal logged"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(meal?.displayEmoji ?? "✓")
                Text(displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggested Meal Card

struct SuggestedMealCard: View {
    let meal: SuggestedFoodEntry
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text(meal.displayEmoji)
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.circle)
                }
            }

            // Meal name and calories
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.headline)

                    if let servingSize = meal.servingSize {
                        Text(servingSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(meal.calories)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Macros
            HStack(spacing: 16) {
                MealMacroPill(label: "Protein", value: Int(meal.proteinGrams), color: .blue)
                MealMacroPill(label: "Carbs", value: Int(meal.carbsGrams), color: .green)
                MealMacroPill(label: "Fat", value: Int(meal.fatGrams), color: .yellow)
            }

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    onEdit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                        Text("Edit")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                        Text("Log")
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
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Meal Macro Pill

struct MealMacroPill: View {
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

// MARK: - Edit Meal Suggestion Sheet

struct EditMealSuggestionSheet: View {
    let meal: SuggestedFoodEntry
    let onSave: (SuggestedFoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var servingSize: String

    init(meal: SuggestedFoodEntry, onSave: @escaping (SuggestedFoodEntry) -> Void) {
        self.meal = meal
        self.onSave = onSave
        _name = State(initialValue: meal.name)
        _caloriesText = State(initialValue: String(meal.calories))
        _proteinText = State(initialValue: String(format: "%.0f", meal.proteinGrams))
        _carbsText = State(initialValue: String(format: "%.0f", meal.carbsGrams))
        _fatText = State(initialValue: String(format: "%.0f", meal.fatGrams))
        _servingSize = State(initialValue: meal.servingSize ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(caloriesText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food Details") {
                    TextField("Name", text: $name)
                    TextField("Serving Size (optional)", text: $servingSize)
                }

                Section("Nutrition") {
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

                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $proteinText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let updated = SuggestedFoodEntry(
                            name: name.trimmingCharacters(in: .whitespaces),
                            calories: Int(caloriesText) ?? meal.calories,
                            proteinGrams: Double(proteinText) ?? meal.proteinGrams,
                            carbsGrams: Double(carbsText) ?? meal.carbsGrams,
                            fatGrams: Double(fatText) ?? meal.fatGrams,
                            servingSize: servingSize.isEmpty ? nil : servingSize
                        )
                        onSave(updated)
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Memory Saved Badge

struct MemorySavedBadge: View {
    let memories: [String]

    private var displayText: String {
        if memories.count == 1 {
            return "Remembered"
        }
        return "Remembered \(memories.count) things"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.1))
        .clipShape(.capsule)
    }
}
