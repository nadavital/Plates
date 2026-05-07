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

    private var canSend: Bool {
        (!draftText.trimmingCharacters(in: .whitespaces).isEmpty || selectedImage != nil) && !isLoading
    }

    private var inputCornerRadius: CGFloat {
        min(inputBarHeight / 2, 26)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                // Add button with menu
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

                composerField
            }
            .animation(.snappy(duration: 0.2), value: isLoading)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
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

                        Spacer()
                    }
                }

                TextField("Message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused(isFocused)
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
        } else {
            Button {
                let outgoingText = draftText
                draftText = ""
                onSend(outgoingText)
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
            .transition(.scale.combined(with: .opacity))
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
    }
}
