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
    var onAddFood: (() -> Void)?
    var onAddToSession: ((UUID) -> Void)?
    let onEditEntry: (FoodEntry) -> Void
    let onDeleteEntry: (FoodEntry) -> Void

    /// Group entries: sessions first, then individual entries
    private var groupedEntries: [FoodGroup] {
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
                                onTap: { onEditEntry(entry) },
                                onDelete: { onDeleteEntry(entry) }
                            )

                        case .session(let sessionId, let sessionEntries):
                            FoodSessionCard(
                                entries: sessionEntries,
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

// MARK: - Food Group Type

private enum FoodGroup: Identifiable {
    case single(FoodEntry)
    case session(id: UUID, entries: [FoodEntry])

    var id: String {
        switch self {
        case .single(let entry):
            return entry.id.uuidString
        case .session(let id, _):
            return "session-\(id.uuidString)"
        }
    }
}

// MARK: - Empty Meals View

private struct EmptyMealsView: View {
    var onAddFood: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(onAddFood != nil ? "No meals logged yet" : "No meals logged")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let addAction = onAddFood {
                Button("Log Your First Meal", action: addAction)
                    .font(.subheadline)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Food Session Card

private struct FoodSessionCard: View {
    let entries: [FoodEntry]
    var onAddMore: (() -> Void)?
    let onEditEntry: (FoodEntry) -> Void
    let onDeleteEntry: (FoodEntry) -> Void

    @State private var isExpanded = true

    private var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        entries.reduce(0) { $0 + $1.proteinGrams }
    }

    private var sessionTime: Date {
        entries.first?.loggedAt ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session header
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
                HapticManager.selectionChanged()
            } label: {
                HStack(spacing: 10) {
                    // Stack icon for grouped items
                    Image(systemName: "square.stack.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meal (\(entries.count) items)")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.primary)

                        Text(sessionTime, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalCalories) kcal")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Text("\(Int(totalProtein))g protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Expanded entries
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        SessionEntryRow(
                            entry: entry,
                            onTap: { onEditEntry(entry) },
                            onDelete: { onDeleteEntry(entry) }
                        )
                    }

                    // Add more button (only if onAddMore is provided)
                    if let addAction = onAddMore {
                        Button(action: addAction) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to this meal")
                            }
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Session Entry Row

private struct SessionEntryRow: View {
    let entry: FoodEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Food image or emoji
                Group {
                    if let imageData = entry.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(entry.displayEmoji)
                            .font(.system(size: 16))
                    }
                }
                .frame(width: 28, height: 28)
                .background(Color(.quaternarySystemFill))
                .clipShape(.rect(cornerRadius: 4))

                Text(entry.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text("\(entry.calories)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { showingDeleteConfirm = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.quaternarySystemFill))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete \(entry.name)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Food Entry Timeline Row

private struct FoodEntryTimelineRow: View {
    let entry: FoodEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

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
                            .font(.system(size: 24))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color(.quaternarySystemFill))
                .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let serving = entry.servingSize {
                            Text(serving)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(entry.loggedAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.calories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text("\(Int(entry.proteinGrams))g protein")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Delete button
                Button(action: { showingDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete \(entry.name)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
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
