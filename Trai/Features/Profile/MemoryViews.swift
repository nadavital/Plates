//
//  MemoryViews.swift
//  Trai
//
//  Memory management UI components for viewing, editing, and deleting coach memories
//

import SwiftUI
import SwiftData

// MARK: - Memory Row

struct MemoryRow: View {
    let memory: CoachMemory
    let onDelete: () -> Void
    var onUpdate: () -> Void = {}

    @State private var showDeleteConfirmation = false
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
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
                        .foregroundStyle(.primary)

                    Text(memory.topic.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        }
        .buttonStyle(.plain)
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
        .sheet(isPresented: $showDetail) {
            MemoryDetailSheet(memory: memory, onDelete: {
                showDetail = false
                onDelete()
            }, onUpdate: {
                onUpdate()
            })
            .presentationDetents([.medium])
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
    @Environment(\.modelContext) private var modelContext
    @State private var memories: [CoachMemory] = []

    var body: some View {
        List {
            ForEach(MemoryTopic.allCases) { topic in
                let topicMemories = memories.filter { $0.topic == topic }
                if !topicMemories.isEmpty {
                    Section {
                        ForEach(topicMemories) { memory in
                            MemoryListRow(memory: memory, onDelete: {
                                deleteMemory(memory)
                            }, onUpdate: {
                                fetchMemories()
                            })
                        }
                    } header: {
                        Label(topic.displayName, systemImage: topicIcon(topic))
                    }
                }
            }
        }
        .navigationTitle("All Memories")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchMemories()
        }
    }

    private func fetchMemories() {
        let descriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        memories = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteMemory(_ memory: CoachMemory) {
        memory.isActive = false
        HapticManager.lightTap()
        // Refresh the list
        fetchMemories()
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
    var onUpdate: () -> Void = {}

    @State private var showDeleteConfirmation = false
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: memory.category.icon)
                    .font(.caption)
                    .foregroundStyle(categoryColor)
                    .frame(width: 24, height: 24)
                    .background(categoryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Text(memory.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
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
        .sheet(isPresented: $showDetail) {
            MemoryDetailSheet(memory: memory, onDelete: {
                showDetail = false
                onDelete()
            }, onUpdate: {
                onUpdate()
            })
            .presentationDetents([.medium])
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

// MARK: - Memory Detail Sheet

struct MemoryDetailSheet: View {
    let memory: CoachMemory
    let onDelete: () -> Void
    var onUpdate: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Category and topic header
                    HStack(spacing: 12) {
                        Image(systemName: memory.category.icon)
                            .font(.title2)
                            .foregroundStyle(categoryColor)
                            .frame(width: 44, height: 44)
                            .background(categoryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(memory.category.displayName)
                                .font(.headline)
                            Text(memory.topic.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Full memory content
                    Text(memory.content)
                        .font(.body)

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Saved \(memory.createdAt.formatted(date: .long, time: .shortened))", systemImage: "calendar")
                        Label("Source: \(memory.source.capitalized)", systemImage: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit", systemImage: "pencil") {
                        showEditSheet = true
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .tint(.accentColor)
                }

                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .confirmationDialog("Delete Memory", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this memory?")
            }
            .sheet(isPresented: $showEditSheet) {
                MemoryEditSheet(memory: memory) {
                    onUpdate()
                }
                .presentationDetents([.medium, .large])
            }
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

// MARK: - Memory Edit Sheet

struct MemoryEditSheet: View {
    let memory: CoachMemory
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draftContent: String
    @State private var draftCategory: MemoryCategory
    @State private var draftTopic: MemoryTopic
    @State private var draftImportance: Int

    init(memory: CoachMemory, onSave: @escaping () -> Void) {
        self.memory = memory
        self.onSave = onSave
        _draftContent = State(initialValue: memory.content)
        _draftCategory = State(initialValue: memory.category)
        _draftTopic = State(initialValue: memory.topic)
        _draftImportance = State(initialValue: memory.importance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("What should Trai remember?", text: $draftContent, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Classification") {
                    Picker("Category", selection: $draftCategory) {
                        ForEach(MemoryCategory.allCases, id: \.rawValue) { category in
                            Text(category.displayName).tag(category)
                        }
                    }

                    Picker("Topic", selection: $draftTopic) {
                        ForEach(MemoryTopic.allCases, id: \.rawValue) { topic in
                            Text(topic.displayName).tag(topic)
                        }
                    }
                }

                Section("Priority") {
                    Stepper(value: $draftImportance, in: 1...5) {
                        Text("Importance \(draftImportance)")
                    }
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .tint(.accentColor)
                    .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveChanges() {
        let trimmedContent = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        memory.content = trimmedContent
        memory.category = draftCategory
        memory.topic = draftTopic
        memory.importance = draftImportance

        try? modelContext.save()
        onSave()
        HapticManager.lightTap()
        dismiss()
    }
}
