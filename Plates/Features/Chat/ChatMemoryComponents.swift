//
//  ChatMemoryComponents.swift
//  Plates
//
//  Memory-related UI components for chat
//

import SwiftUI
import SwiftData

// MARK: - Memory Saved Badge

struct MemorySavedBadge: View {
    let memories: [String]
    @Environment(\.modelContext) private var modelContext
    @State private var showMemories = false
    @State private var singleMemory: CoachMemory?

    private var displayText: String {
        if memories.count == 1 {
            return "Remembered"
        }
        return "Remembered \(memories.count) things"
    }

    var body: some View {
        Button {
            if memories.count == 1 {
                fetchSingleMemory()
            } else {
                showMemories = true
            }
        } label: {
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
        .buttonStyle(.plain)
        .sheet(isPresented: $showMemories) {
            SavedMemoriesSheet(memoryContents: memories)
                .presentationDetents([.medium])
        }
        .sheet(item: $singleMemory) { memory in
            MemoryDetailSheet(memory: memory, onDelete: {
                memory.isActive = false
                try? modelContext.save()
                singleMemory = nil
                HapticManager.lightTap()
            })
            .presentationDetents([.medium])
        }
    }

    private func fetchSingleMemory() {
        guard let content = memories.first else { return }
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allMemories = (try? modelContext.fetch(descriptor)) ?? []
        singleMemory = allMemories.first { $0.content == content }
    }
}

// MARK: - Saved Memories Sheet

struct SavedMemoriesSheet: View {
    let memoryContents: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var memories: [CoachMemory] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(memories) { memory in
                    MemoryListRow(memory: memory, onDelete: {
                        deleteMemory(memory)
                    })
                }
            }
            .navigationTitle("Saved Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchMemories()
            }
        }
    }

    private func fetchMemories() {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allMemories = (try? modelContext.fetch(descriptor)) ?? []
        memories = allMemories.filter { memoryContents.contains($0.content) }
    }

    private func deleteMemory(_ memory: CoachMemory) {
        memory.isActive = false
        try? modelContext.save()
        fetchMemories()
        HapticManager.lightTap()
    }
}
