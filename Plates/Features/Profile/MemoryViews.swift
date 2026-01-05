//
//  MemoryViews.swift
//  Plates
//
//  Memory management UI components for viewing and deleting coach memories
//

import SwiftUI

// MARK: - Memory Row

struct MemoryRow: View {
    let memory: CoachMemory
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: memory.category.icon)
                .font(.body)
                .foregroundStyle(categoryColor)
                .frame(width: 32, height: 32)
                .background(categoryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.content)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(memory.topic.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(memory.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Delete Memory", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this memory? Trai will no longer remember this about you.")
        }
    }

    private var categoryColor: Color {
        switch memory.category {
        case .preference: return .pink
        case .restriction: return .red
        case .habit: return .orange
        case .goal: return .blue
        case .context: return .purple
        case .feedback: return .green
        }
    }
}

// MARK: - All Memories View

struct AllMemoriesView: View {
    let memories: [CoachMemory]
    let onDelete: (CoachMemory) -> Void

    private var groupedMemories: [(topic: MemoryTopic, memories: [CoachMemory])] {
        let grouped = Dictionary(grouping: memories) { $0.topic }
        return MemoryTopic.allCases.compactMap { topic in
            guard let topicMemories = grouped[topic], !topicMemories.isEmpty else { return nil }
            return (topic: topic, memories: topicMemories.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        List {
            ForEach(groupedMemories, id: \.topic) { group in
                Section {
                    ForEach(group.memories) { memory in
                        MemoryListRow(memory: memory, onDelete: {
                            onDelete(memory)
                        })
                    }
                } header: {
                    Label(group.topic.displayName, systemImage: topicIcon(group.topic))
                }
            }
        }
        .navigationTitle("All Memories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func topicIcon(_ topic: MemoryTopic) -> String {
        switch topic {
        case .food: return "fork.knife"
        case .workout: return "figure.run"
        case .schedule: return "calendar"
        case .general: return "person.fill"
        }
    }
}

// MARK: - Memory List Row (for full list view)

struct MemoryListRow: View {
    let memory: CoachMemory
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: memory.category.icon)
                .font(.caption)
                .foregroundStyle(categoryColor)
                .frame(width: 24, height: 24)
                .background(categoryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(memory.content)
                    .font(.subheadline)

                Text(memory.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Memory", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this memory?")
        }
    }

    private var categoryColor: Color {
        switch memory.category {
        case .preference: return .pink
        case .restriction: return .red
        case .habit: return .orange
        case .goal: return .blue
        case .context: return .purple
        case .feedback: return .green
        }
    }
}
