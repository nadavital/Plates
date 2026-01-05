//
//  TraiFAB.swift
//  Plates
//
//  Floating action button with Trai's animated lens
//

import SwiftUI

/// Floating Trai button that opens the chat
struct TraiFAB: View {
    let onTap: () -> Void
    var isThinking: Bool = false

    private var lensState: TraiLensState {
        isThinking ? .thinking : .idle
    }

    var body: some View {
        Button(action: onTap) {
            TraiLensView(size: 56, state: lensState, palette: .energy)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .shadow(color: Color.red.opacity(0.2), radius: 12, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with Trai")
    }
}

/// Container view that adds the Trai FAB overlay to any content
struct TraiFABContainer<Content: View>: View {
    @ViewBuilder let content: Content
    let onTraiTapped: () -> Void
    var isThinking: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            TraiFAB(onTap: onTraiTapped, isThinking: isThinking)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack {
            Text("Dashboard Content")
                .foregroundStyle(.secondary)
        }

        VStack {
            Spacer()
            HStack {
                Spacer()
                TraiFAB(onTap: {})
                    .padding()
            }
        }
    }
}
