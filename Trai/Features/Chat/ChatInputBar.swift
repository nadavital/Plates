//
//  ChatInputBar.swift
//  Trai
//
//  Chat input bar with text field and attachment options
//

import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var selectedImage: UIImage?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let isLoading: Bool
    let onSend: (String) -> Void
    let onStop: (() -> Void)?
    let onTakePhoto: () -> Void
    let onImageTapped: (UIImage) -> Void
    var isFocused: FocusState<Bool>.Binding

    @State private var showingPhotoPicker = false
    @State private var draftText = ""
    @State private var inputBarHeight: CGFloat = 52
    @State private var renderedDictationText = ""
    @StateObject private var dictation = ChatDictationController()

    private var canSend: Bool {
        (!draftText.trimmingCharacters(in: .whitespaces).isEmpty || selectedImage != nil) && !isLoading
    }

    private var inputCornerRadius: CGFloat {
        min(inputBarHeight / 2, 26)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                attachmentOrDictationStopButton

                composerField
            }
            .animation(.snappy(duration: 0.2), value: isLoading)
            .animation(.snappy(duration: 0.18), value: dictation.isRecording)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onDisappear {
            dictation.stop()
            renderedDictationText = ""
        }
    }

    @ViewBuilder
    private var attachmentOrDictationStopButton: some View {
        if dictation.isRecording || dictation.isPreparing {
            Button {
                Task {
                    await dictation.finish()
                    renderedDictationText = ""
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(.red).interactive(), in: .circle)
            .accessibilityLabel("Stop dictation")
        } else {
            Menu {
                Button("Take Photo", systemImage: "camera") {
                    onTakePhoto()
                }

                Button("Choose from Library", systemImage: "photo.on.rectangle") {
                    showingPhotoPicker = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(.red).interactive(), in: .circle)
            .opacity(isLoading ? 0.5 : 1)
            .disabled(isLoading)
            .accessibilityLabel("Add attachment")
        }
    }

    private var composerField: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if let image = selectedImage {
                    HStack(spacing: 8) {
                        Button {
                            onImageTapped(image)
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(.rect(cornerRadius: 8))
                        }
                        .accessibilityLabel("Preview attached image")

                        Button {
                            withAnimation(.snappy) {
                                selectedImage = nil
                                selectedPhotoItem = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5), in: .circle)
                        }
                        .accessibilityLabel("Remove attached image")

                        Spacer()
                    }
                }

                TextField("Message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused(isFocused)
            }

            if !isLoading {
                if !dictation.isRecording {
                    dictationButton(text: $draftText, isDisabled: false)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            sendOrStopButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassEffect(
            .regular
                .tint(Color.white.opacity(0.08))
                .interactive(),
            in: .rect(cornerRadius: inputCornerRadius)
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            inputBarHeight = newHeight
        }
        .animation(.snappy(duration: 0.18), value: inputCornerRadius)
    }

    @ViewBuilder
    private var sendOrStopButton: some View {
        if isLoading, let onStop {
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(.red).interactive(), in: .circle)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Stop response")
        } else {
            Button {
                Task {
                    await dictation.finish()
                    let outgoingText = draftText
                    renderedDictationText = ""
                    draftText = ""
                    onSend(outgoingText)
                    isFocused.wrappedValue = false
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(canSend ? .accent : .gray).interactive(), in: .circle)
            .opacity(canSend ? 1 : 0.5)
            .disabled(!canSend)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Send message")
        }
    }

    private func dictationButton(text: Binding<String>, isDisabled: Bool) -> some View {
        ChatDictationButton(
            isRecording: dictation.isRecording,
            isPreparing: dictation.isPreparing,
            isDisabled: isDisabled
        ) {
            if dictation.isRecording {
                Task {
                    await dictation.finish()
                    renderedDictationText = ""
                }
            } else {
                isFocused.wrappedValue = true
                renderedDictationText = ""
                dictation.start { transcript in
                    text.wrappedValue = text.wrappedValue.replacingDictationTranscript(
                        previous: renderedDictationText,
                        with: transcript
                    )
                    renderedDictationText = transcript
                }
            }
        }
    }
}

// MARK: - Simple Chat Input Bar (Text Only)

/// A simpler version of the chat input bar without photo options
/// Used for plan customization, workout chat, etc.
struct SimpleChatInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isLoading: Bool
    let onSend: () -> Void
    var isFocused: FocusState<Bool>.Binding
    @State private var inputBarHeight: CGFloat = 52
    @State private var renderedDictationText = ""
    @StateObject private var dictation = ChatDictationController()

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    private var inputCornerRadius: CGFloat {
        min(inputBarHeight / 2, 26)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused(isFocused)

                dictationButton

                Button {
                    Task {
                        await dictation.finish()
                        renderedDictationText = ""
                        onSend()
                        isFocused.wrappedValue = false
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .glassEffect(.regular.tint(canSend ? .accent : .gray).interactive(), in: .circle)
                .opacity(canSend ? 1 : 0.5)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(
                .regular
                    .tint(Color.white.opacity(0.08))
                    .interactive(),
                in: .rect(cornerRadius: inputCornerRadius)
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { _, newHeight in
                inputBarHeight = newHeight
            }
            .animation(.snappy(duration: 0.18), value: inputCornerRadius)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onDisappear {
            dictation.stop()
            renderedDictationText = ""
        }
    }

    private var dictationButton: some View {
        ChatDictationButton(
            isRecording: dictation.isRecording,
            isPreparing: dictation.isPreparing,
            isDisabled: isLoading
        ) {
            if dictation.isRecording {
                Task {
                    await dictation.finish()
                    renderedDictationText = ""
                }
            } else {
                isFocused.wrappedValue = true
                renderedDictationText = ""
                dictation.start { transcript in
                    text = text.replacingDictationTranscript(
                        previous: renderedDictationText,
                        with: transcript
                    )
                    renderedDictationText = transcript
                }
            }
        }
    }
}

private struct ChatDictationButton: View {
    let isRecording: Bool
    let isPreparing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            dictationIcon
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isPreparing)
        .opacity(isDisabled || isPreparing ? 0.55 : 1)
        .animation(.snappy(duration: 0.18), value: isRecording)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var dictationIcon: some View {
        if isPreparing {
            ProgressView()
                .controlSize(.mini)
        } else if isRecording {
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.red)
        } else {
            Image(systemName: "mic")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.red)
        }
    }

    private var accessibilityLabel: String {
        if isPreparing {
            "Preparing dictation"
        } else if isRecording {
            "Stop dictation"
        } else {
            "Start dictation"
        }
    }
}

private extension String {
    func replacingDictationTranscript(previous: String, with transcript: String) -> String {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !previous.isEmpty else {
            return appendingDictationText(transcript)
        }

        if hasSuffix(previous) {
            let base = String(dropLast(previous.count))
            return base.appendingDictationText(transcript)
        }

        let delta = previous.incrementalText(to: transcript)
        return appendingDictationText(delta)
    }

    func appendingDictationText(_ spokenText: String) -> String {
        let spokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return self }

        let trimmedSelf = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelf.isEmpty else { return spokenText }

        return self + (endsWithWhitespace ? "" : " ") + spokenText
    }

    private var endsWithWhitespace: Bool {
        guard let last else { return true }
        return last.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private func incrementalText(to currentText: String) -> String {
        let previous = trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return "" }
        guard !previous.isEmpty else { return current }

        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var previousIndex = previous.startIndex
        var currentIndex = current.startIndex
        while previousIndex < previous.endIndex,
              currentIndex < current.endIndex,
              previous[previousIndex] == current[currentIndex] {
            previousIndex = previous.index(after: previousIndex)
            currentIndex = current.index(after: currentIndex)
        }

        return String(current[currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
