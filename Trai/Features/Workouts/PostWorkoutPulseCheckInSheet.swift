//
//  PostWorkoutPulseCheckInSheet.swift
//  Trai
//
//  Quick post-workout check-in that feeds Trai Pulse context.
//

import SwiftUI

struct PostWorkoutPulseCheckInData: Sendable {
    let selectedTags: [String]
    let discomfort: Int
    let note: String
}

struct PostWorkoutPulseCheckInSheet: View {
    let onSubmit: (PostWorkoutPulseCheckInData) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: Set<String> = []
    @State private var discomfort: Double = 3
    @State private var note: String = ""

    private let tagOptions = [
        "Shoulder felt off",
        "Knee felt off",
        "Low back tight",
        "Energy crashed",
        "Felt great"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Quick Pulse Check-In")
                    .font(.headline)

                Text("Help Trai adjust your next recommendation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("What stood out?")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(tagOptions, id: \.self) { option in
                                Button(option) {
                                    if selectedTags.contains(option) {
                                        selectedTags.remove(option)
                                    } else {
                                        selectedTags.insert(option)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedTags.contains(option) ? .accentColor : .gray)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.hidden)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Discomfort level")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Slider(value: $discomfort, in: 0...10, step: 1)

                    Text("\(Int(discomfort)) / 10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional note")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    TextField("Anything Trai should remember for tomorrow?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSubmit(
                            PostWorkoutPulseCheckInData(
                                selectedTags: selectedTags.sorted(),
                                discomfort: Int(discomfort.rounded()),
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        dismiss()
                    }
                    .tint(.accentColor)
                }
            }
        }
    }
}

#Preview {
    PostWorkoutPulseCheckInSheet(
        onSubmit: { _ in },
        onSkip: {}
    )
}
