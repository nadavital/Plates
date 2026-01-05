//
//  CalorieDetailSheet.swift
//  Plates
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData

struct CalorieDetailSheet: View {
    let entries: [FoodEntry]
    let goal: Int
    var onAddFood: (() -> Void)?
    let onEditEntry: (FoodEntry) -> Void
    let onDeleteEntry: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    private var consumed: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    private var remaining: Int {
        max(goal - consumed, 0)
    }

    private var progress: Double {
        min(Double(consumed) / Double(goal), 1.0)
    }

    /// Entries sorted chronologically (most recent first)
    private var sortedEntries: [FoodEntry] {
        entries.sorted { $0.loggedAt > $1.loggedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large progress ring
                    CalorieRing(consumed: consumed, goal: goal, remaining: remaining)
                        .frame(height: 200)
                        .padding(.top)

                    // Stats row
                    HStack(spacing: 0) {
                        StatItem(title: "Consumed", value: "\(consumed)", unit: "kcal", color: .primary)
                        Divider()
                            .frame(height: 40)
                        StatItem(title: "Remaining", value: "\(remaining)", unit: "kcal", color: .green)
                        Divider()
                            .frame(height: 40)
                        StatItem(title: "Goal", value: "\(goal)", unit: "kcal", color: .secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))

                    // Food list
                    VStack(alignment: .leading, spacing: 12) {
                        Text(onAddFood != nil ? "Today's Food" : "Food Log")
                            .font(.headline)
                            .padding(.horizontal)

                        if sortedEntries.isEmpty {
                            EmptyStateView(onAddFood: onAddFood)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(sortedEntries) { entry in
                                    FoodCalorieRow(
                                        entry: entry,
                                        onTap: { onEditEntry(entry) },
                                        onDelete: { onDeleteEntry(entry) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Calorie Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }

                if let addAction = onAddFood {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Food", systemImage: "plus", action: addAction)
                    }
                }
            }
        }
    }
}

// MARK: - Calorie Ring

private struct CalorieRing: View {
    let consumed: Int
    let goal: Int
    let remaining: Int

    private var progress: Double {
        min(Double(consumed) / Double(goal), 1.0)
    }

    private var progressColor: Color {
        if progress < 0.8 {
            return .green
        } else if progress < 1.0 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(progressColor.opacity(0.2), lineWidth: 20)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)

            // Center text
            VStack(spacing: 4) {
                Text("\(consumed)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))

                Text("of \(goal) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if remaining > 0 {
                    Text("\(remaining) remaining")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
            }
        }
        .padding(30)
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .bold()
                .foregroundStyle(color)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Food Calorie Row

private struct FoodCalorieRow: View {
    let entry: FoodEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Food image or emoji
                Group {
                    if let imageData = entry.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(entry.displayEmoji)
                            .font(.system(size: 22))
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color(.quaternarySystemFill))
                .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(entry.loggedAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(entry.calories) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var onAddFood: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(onAddFood != nil ? "No food logged today" : "No food logged")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let addAction = onAddFood {
                Button("Log Your First Meal", action: addAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

#Preview {
    CalorieDetailSheet(
        entries: [
            FoodEntry(name: "Oatmeal", mealType: "breakfast", calories: 350, proteinGrams: 12, carbsGrams: 60, fatGrams: 8),
            FoodEntry(name: "Chicken Salad", mealType: "lunch", calories: 450, proteinGrams: 40, carbsGrams: 15, fatGrams: 22),
        ],
        goal: 2000,
        onAddFood: {},
        onEditEntry: { _ in },
        onDeleteEntry: { _ in }
    )
}
