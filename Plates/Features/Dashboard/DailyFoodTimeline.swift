//
//  DailyFoodTimeline.swift
//  Plates
//
//  Created by Nadav Avital on 12/28/25.
//

import SwiftUI
import SwiftData

struct DailyFoodTimeline: View {
    let entries: [FoodEntry]
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    var onAddFood: (() -> Void)?
    var onAddToSession: ((UUID) -> Void)?
    let onEditEntry: (FoodEntry) -> Void
    let onDeleteEntry: (FoodEntry) -> Void

    /// Group entries: sessions first, then individual entries
    var groupedEntries: [FoodGroup] {
        var groups: [FoodGroup] = []
        var processedIds: Set<UUID> = []

        // Get entries sorted by time (newest first)
        let sortedEntries = entries.sorted { $0.loggedAt > $1.loggedAt }

        for entry in sortedEntries {
            guard !processedIds.contains(entry.id) else { continue }

            if let sessionId = entry.sessionId {
                // Find all entries in this session
                let sessionEntries = entries.filter { $0.sessionId == sessionId }
                    .sorted { $0.sessionOrder < $1.sessionOrder }

                if sessionEntries.count > 1 {
                    // Create a session group
                    groups.append(.session(id: sessionId, entries: sessionEntries))
                    sessionEntries.forEach { processedIds.insert($0.id) }
                } else {
                    // Single entry in session, treat as individual
                    groups.append(.single(entry))
                    processedIds.insert(entry.id)
                }
            } else {
                // No session, treat as individual
                groups.append(.single(entry))
                processedIds.insert(entry.id)
            }
        }

        return groups
    }

    private var isEmpty: Bool {
        entries.isEmpty
    }

    private var canAddFood: Bool {
        onAddFood != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(canAddFood ? "Today's Food" : "Food Log")
                    .font(.headline)

                Spacer()

                if let addAction = onAddFood {
                    Button("Add", systemImage: "plus.circle.fill", action: addAction)
                        .font(.subheadline)
                        .labelStyle(.iconOnly)
                }
            }

            if isEmpty {
                EmptyMealsView(onAddFood: onAddFood)
            } else {
                VStack(spacing: 8) {
                    ForEach(groupedEntries) { group in
                        switch group {
                        case .single(let entry):
                            FoodEntryTimelineRow(
                                entry: entry,
                                enabledMacros: enabledMacros,
                                onTap: { onEditEntry(entry) },
                                onDelete: { onDeleteEntry(entry) }
                            )

                        case .session(let sessionId, let sessionEntries):
                            FoodSessionCard(
                                entries: sessionEntries,
                                enabledMacros: enabledMacros,
                                onAddMore: onAddToSession.map { action in { action(sessionId) } },
                                onEditEntry: onEditEntry,
                                onDeleteEntry: onDeleteEntry
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

#Preview {
    let sessionId = UUID()
    return VStack {
        DailyFoodTimeline(
            entries: [
                {
                    let entry = FoodEntry(name: "Oatmeal with Berries", mealType: "breakfast", calories: 350, proteinGrams: 12, carbsGrams: 60, fatGrams: 8)
                    entry.sessionId = sessionId
                    entry.sessionOrder = 0
                    return entry
                }(),
                {
                    let entry = FoodEntry(name: "Greek Yogurt", mealType: "breakfast", calories: 150, proteinGrams: 15, carbsGrams: 10, fatGrams: 5)
                    entry.sessionId = sessionId
                    entry.sessionOrder = 1
                    return entry
                }(),
                FoodEntry(name: "Grilled Chicken Salad", mealType: "lunch", calories: 450, proteinGrams: 40, carbsGrams: 15, fatGrams: 22),
            ],
            onAddFood: {},
            onAddToSession: { _ in },
            onEditEntry: { _ in },
            onDeleteEntry: { _ in }
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
