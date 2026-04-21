//
//  TraiQuestionMessage.swift
//  Trai
//
//  Reusable question message with suggestion chips
//

import SwiftUI

// MARK: - Conversation Message Primitives

/// Shared leading Trai text styling used across chat-like surfaces.
struct TraiAssistantTextMessage: View {
    let text: String
    var font: Font = .body
    var foregroundStyle: Color = .primary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared multi-paragraph Trai text styling used across chat-like surfaces.
struct TraiAssistantParagraphMessage: View {
    let paragraphs: [AttributedString]
    var font: Font = .body
    var foregroundStyle: Color = .primary
    var enableTextSelection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                paragraphView(paragraph)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: AttributedString) -> some View {
        if enableTextSelection {
            Text(paragraph)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .textSelection(.enabled)
        } else {
            Text(paragraph)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .textSelection(.disabled)
        }
    }
}

/// Shared user reply bubble styling used across chat-like surfaces.
struct TraiUserTextBubble: View {
    let text: String
    var enableTextSelection: Bool = false

    var body: some View {
        bubbleText
            .padding(TraiSpacing.md)
            .background(Color.accentColor)
            .clipShape(.rect(cornerRadius: TraiRadius.medium))
    }

    @ViewBuilder
    private var bubbleText: some View {
        if enableTextSelection {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .textSelection(.disabled)
        }
    }
}

// MARK: - Question Message

/// Displays a Trai question with suggestion chips that users can tap to answer
struct TraiQuestionMessage: View {
    let config: TraiQuestionConfig
    @Binding var selectedAnswers: [String]
    var onAnswerSelected: ((String, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question text (like a Trai message)
            TraiAssistantTextMessage(text: config.question)

            // Suggestion chips
            TraiSuggestionChips(
                suggestions: config.suggestions,
                selectionMode: config.selectionMode,
                selectedAnswers: selectedAnswers,
                onTap: handleSuggestionTap
            )

            // Selected answers as removable tags (for multi-select with custom answers)
            if config.selectionMode == .multiple && !selectedAnswers.isEmpty {
                TraiSelectedAnswerTags(
                    answers: selectedAnswers,
                    suggestions: config.suggestions.map(\.text),
                    onRemove: { answer in
                        handleRemove(answer)
                    }
                )
            }
        }
    }

    private func handleSuggestionTap(_ suggestion: TraiSuggestion) {
        switch config.selectionMode {
        case .single:
            selectedAnswers = [suggestion.text]
            onAnswerSelected?(suggestion.text, suggestion.isSkip)

        case .multiple:
            if selectedAnswers.contains(suggestion.text) {
                selectedAnswers.removeAll { $0 == suggestion.text }
            } else {
                selectedAnswers.append(suggestion.text)
            }
            onAnswerSelected?(suggestion.text, suggestion.isSkip)
        }
    }

    private func handleRemove(_ answer: String) {
        selectedAnswers.removeAll { $0 == answer }
    }
}

// MARK: - Suggestion Options

/// List of tappable suggestion options (full-width rows)
struct TraiSuggestionChips: View {
    let suggestions: [TraiSuggestion]
    let selectionMode: TraiSelectionMode
    let selectedAnswers: [String]
    let onTap: (TraiSuggestion) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(suggestions) { suggestion in
                TraiOptionRow(
                    text: suggestion.text,
                    subtitle: suggestion.subtitle,
                    isSelected: selectedAnswers.contains(suggestion.text),
                    isSkip: suggestion.isSkip,
                    selectionMode: selectionMode
                ) {
                    HapticManager.lightTap()
                    onTap(suggestion)
                }
            }
        }
    }
}

// MARK: - Option Row

/// A full-width selectable option row
struct TraiOptionRow: View {
    let text: String
    var subtitle: String? = nil
    let isSelected: Bool
    var isSkip: Bool = false
    let selectionMode: TraiSelectionMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Selection indicator
                selectionIndicator

                // Option text and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.body)
                        .fontWeight(isSelected ? .medium : .regular)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Checkmark for selected state
                if isSelected && !isSkip {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, subtitle != nil ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if selectionMode == .multiple {
            // Checkbox style for multi-select
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 1.5)
                    .frame(width: 22, height: 22)

                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: 22, height: 22)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        } else {
            // Radio button style for single-select
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 1.5)
                    .frame(width: 22, height: 22)

                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                }
            }
        }
    }

    private var backgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        .primary
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor : Color(.tertiarySystemFill)
    }
}

// MARK: - Legacy Chip (for compact use cases)

/// A compact selectable chip (for inline/flow layouts)
struct TraiSelectableChip: View {
    let text: String
    let isSelected: Bool
    var isSkip: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected && !isSkip {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(text)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSkip {
            return Color(.tertiarySystemFill)
        }
        return isSelected ? Color.accentColor : Color(.tertiarySystemFill)
    }

    private var foregroundColor: Color {
        if isSkip {
            return .secondary
        }
        return isSelected ? .white : .primary
    }
}

// MARK: - Selected Answer Tags

/// Shows selected answers as removable tags (only for custom/typed answers not in suggestions)
struct TraiSelectedAnswerTags: View {
    let answers: [String]
    let suggestions: [String]
    let onRemove: (String) -> Void

    /// Only show tags for custom answers (not chip suggestions)
    private var customAnswers: [String] {
        answers.filter { !suggestions.contains($0) }
    }

    var body: some View {
        if !customAnswers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your answers:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(customAnswers, id: \.self) { answer in
                        TraiRemovableTag(text: answer) {
                            onRemove(answer)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Removable Tag

/// A tag showing a selected answer with an X button to remove
struct TraiRemovableTag: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline)

            Button(action: {
                HapticManager.lightTap()
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .clipShape(.capsule)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        TraiQuestionMessage(
            config: TraiQuestionConfig(
                id: "workout_type",
                question: "What type of training are you into?",
                suggestions: [
                    TraiSuggestion("Strength"),
                    TraiSuggestion("Cardio"),
                    TraiSuggestion("HIIT"),
                    TraiSuggestion("Flexibility"),
                    TraiSuggestion("Mixed")
                ],
                selectionMode: .multiple
            ),
            selectedAnswers: .constant(["Strength", "Cardio"])
        )

        TraiQuestionMessage(
            config: TraiQuestionConfig(
                id: "experience",
                question: "How would you describe your experience level?",
                suggestions: [
                    TraiSuggestion("Beginner"),
                    TraiSuggestion("Intermediate"),
                    TraiSuggestion("Advanced")
                ],
                selectionMode: .single
            ),
            selectedAnswers: .constant(["Intermediate"])
        )
    }
    .padding()
}
