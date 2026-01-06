//
//  FoodTimelineComponents.swift
//  Plates
//
//  Components for the daily food timeline
//

import SwiftUI
import SwiftData

// MARK: - Food Group Type

enum FoodGroup: Identifiable {
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

struct EmptyMealsView: View {
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

struct FoodSessionCard: View {
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
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
                HapticManager.selectionChanged()
            } label: {
                HStack(spacing: 10) {
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

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        SessionEntryRow(
                            entry: entry,
                            onTap: { onEditEntry(entry) },
                            onDelete: { onDeleteEntry(entry) }
                        )
                    }

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

struct SessionEntryRow: View {
    let entry: FoodEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
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

struct FoodEntryTimelineRow: View {
    let entry: FoodEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
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
