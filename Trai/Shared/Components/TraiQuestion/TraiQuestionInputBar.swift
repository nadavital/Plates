//
//  TraiQuestionInputBar.swift
//  Trai
//
//  Dynamic input bar for question flows (shows Send/Continue/Skip based on state)
//

import SwiftUI

/// Input bar that adapts its button based on the current question state
struct TraiQuestionInputBar: View {
    @Binding var text: String
    let placeholder: String
    let hasAnswers: Bool
    let isLastQuestion: Bool
    let isLoading: Bool
    let onSend: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void
    var allowsSkipping = true
    var isFocused: FocusState<Bool>.Binding

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Text input
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .focused(isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 20))
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }
                    .disabled(isLoading)

                // Dynamic button
                if canSend {
                    sendButton
                } else {
                    continueOrSkipButton
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Send Button (when typing)

    private var sendButton: some View {
        Button {
            onSend()
            isFocused.wrappedValue = false
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
        }
        .glassEffect(.regular.tint(.accent).interactive(), in: .circle)
        .disabled(isLoading)
    }

    // MARK: - Continue/Skip Button (when not typing)

    private var continueOrSkipButton: some View {
        Button {
            if hasAnswers || (isLastQuestion && allowsSkipping) {
                onContinue()
            } else if allowsSkipping {
                onSkip()
            }
        } label: {
            HStack(spacing: 6) {
                Text(buttonText)
                    .fontWeight(.semibold)

                if hasAnswers || isLastQuestion {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .glassEffect(
            .regular.tint(buttonTint).interactive(),
            in: .capsule
        )
        .disabled(isLoading || (!allowsSkipping && !hasAnswers))
    }

    private var buttonText: String {
        if isLastQuestion {
            return "Generate Plan"
        } else if hasAnswers {
            return "Continue"
        } else if !allowsSkipping {
            return "Continue"
        } else {
            return "Skip"
        }
    }

    private var buttonTint: Color {
        if !allowsSkipping && !hasAnswers {
            return .gray
        }
        if isLastQuestion || hasAnswers {
            return .accentColor
        }
        return .gray
    }
}

// MARK: - Simple Version (for freeform chat after questions)

/// Simpler input bar for after questions are done (just text + send)
struct TraiChatInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isLoading: Bool
    let onSend: () -> Void
    var isFocused: FocusState<Bool>.Binding

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 20))

            Button {
                onSend()
                isFocused.wrappedValue = false
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(canSend ? .accent : .gray).interactive(), in: .circle)
            .opacity(canSend ? 1 : 0.5)
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        // With answers selected
        TraiQuestionInputBar(
            text: .constant(""),
            placeholder: "Type your answer...",
            hasAnswers: true,
            isLastQuestion: false,
            isLoading: false,
            onSend: {},
            onContinue: {},
            onSkip: {},
            isFocused: FocusState<Bool>().projectedValue
        )

        // Without answers (skip mode)
        TraiQuestionInputBar(
            text: .constant(""),
            placeholder: "Type your answer...",
            hasAnswers: false,
            isLastQuestion: false,
            isLoading: false,
            onSend: {},
            onContinue: {},
            onSkip: {},
            isFocused: FocusState<Bool>().projectedValue
        )

        // Last question
        TraiQuestionInputBar(
            text: .constant(""),
            placeholder: "Any final thoughts?",
            hasAnswers: true,
            isLastQuestion: true,
            isLoading: false,
            onSend: {},
            onContinue: {},
            onSkip: {},
            isFocused: FocusState<Bool>().projectedValue
        )
    }
}
