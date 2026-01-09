//
//  ChatInputBar.swift
//  Plates
//
//  Chat input bar with text field and attachment options
//

import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var selectedImage: UIImage?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let isLoading: Bool
    let onSend: () -> Void
    let onTakePhoto: () -> Void
    let onImageTapped: (UIImage) -> Void
    var isFocused: FocusState<Bool>.Binding

    @State private var showingPhotoPicker = false

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespaces).isEmpty || selectedImage != nil) && !isLoading
    }

    private let minInputHeight: CGFloat = 36

    var body: some View {
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

            // Text input with optional image preview
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

                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: minInputHeight)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 20))

            // Send button
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
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Text input
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 20))

            // Send button
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
