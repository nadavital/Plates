//
//  ChatHistoryMenu.swift
//  Trai
//
//  Chat session history menu for toolbar
//

import SwiftUI

struct ChatHistoryMenu: View {
    let sessions: [(id: UUID, firstMessage: String, date: Date)]
    let onSelectSession: (UUID) -> Void
    let onClearHistory: () -> Void
    let onNewChat: () -> Void
    @State private var isShowingClearConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                if sessions.isEmpty {
                    Text("No chat history")
                } else {
                    ForEach(sessions.prefix(10), id: \.id) { session in
                        Button {
                            onSelectSession(session.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sessionTitle(session))
                                Text(session.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Button("Clear All History", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }

            Button("New Chat", systemImage: "square.and.pencil") {
                onNewChat()
            }
        }
        .confirmationDialog(
            "Clear Chat History?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                onClearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all saved chats on this device.")
        }
    }

    private func sessionTitle(_ session: (id: UUID, firstMessage: String, date: Date)) -> String {
        let message = session.firstMessage
        if message.count > 40 {
            return String(message.prefix(40)) + "..."
        }
        return message
    }
}
