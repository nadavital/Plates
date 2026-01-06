//
//  ProfileChatHistory.swift
//  Plates
//
//  Chat history components for the Profile view
//

import SwiftUI
import SwiftData

// MARK: - Chat Session Row

struct ChatSessionRow: View {
    let session: (id: UUID, firstMessage: String, date: Date, messageCount: Int)
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(session.date, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\(session.messageCount) messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
        .confirmationDialog("Delete Chat", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all messages in this conversation.")
        }
    }

    private var sessionTitle: String {
        let message = session.firstMessage
        if message.count > 50 {
            return String(message.prefix(50)) + "..."
        }
        return message.isEmpty ? "Empty chat" : message
    }
}

// MARK: - All Chat Sessions View

struct AllChatSessionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var chatMessages: [ChatMessage] = []

    private var sessions: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] {
        var sessionMap: [UUID: (firstMessage: String, date: Date, messageCount: Int)] = [:]

        for message in chatMessages {
            guard let sessionId = message.sessionId else { continue }
            if let existing = sessionMap[sessionId] {
                sessionMap[sessionId] = (existing.firstMessage, existing.date, existing.messageCount + 1)
            } else {
                sessionMap[sessionId] = (message.content, message.timestamp, 1)
            }
        }

        return sessionMap
            .map { (id: $0.key, firstMessage: $0.value.firstMessage, date: $0.value.date, messageCount: $0.value.messageCount) }
            .sorted { $0.date > $1.date }
    }

    private var groupedSessions: [(title: String, sessions: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek)!

        var today: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] = []
        var yesterday: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] = []
        var thisWeek: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] = []
        var lastWeek: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] = []
        var earlier: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)] = []

        for session in sessions {
            if session.date >= startOfToday {
                today.append(session)
            } else if session.date >= startOfYesterday {
                yesterday.append(session)
            } else if session.date >= startOfThisWeek {
                thisWeek.append(session)
            } else if session.date >= startOfLastWeek {
                lastWeek.append(session)
            } else {
                earlier.append(session)
            }
        }

        var result: [(title: String, sessions: [(id: UUID, firstMessage: String, date: Date, messageCount: Int)])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !lastWeek.isEmpty { result.append(("Last Week", lastWeek)) }
        if !earlier.isEmpty { result.append(("Earlier", earlier)) }

        return result
    }

    var body: some View {
        List {
            ForEach(groupedSessions, id: \.title) { group in
                Section {
                    ForEach(group.sessions, id: \.id) { session in
                        ChatSessionListRow(session: session) {
                            deleteSession(session.id)
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Chat History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchMessages()
        }
    }

    private func fetchMessages() {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        chatMessages = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteSession(_ sessionId: UUID) {
        let messagesToDelete = chatMessages.filter { $0.sessionId == sessionId }
        for message in messagesToDelete {
            modelContext.delete(message)
        }
        HapticManager.lightTap()
        fetchMessages()
    }
}

// MARK: - Chat Session List Row

struct ChatSessionListRow: View {
    let session: (id: UUID, firstMessage: String, date: Date, messageCount: Int)
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(session.date, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\(session.messageCount) messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Chat", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all messages in this conversation.")
        }
    }

    private var sessionTitle: String {
        let message = session.firstMessage
        if message.count > 50 {
            return String(message.prefix(50)) + "..."
        }
        return message.isEmpty ? "Empty chat" : message
    }
}
