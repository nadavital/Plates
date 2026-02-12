//
//  PulsePromptContainer.swift
//  Trai
//
//  Wrapper for inline Pulse prompt interactions.
//

import SwiftUI

struct PulsePromptContainer<Content: View>: View {
    let prompt: String
    let style: TraiPulseSurfaceType
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            content
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(PulseTheme.surfaceTint(style).opacity(0.46))
                .frame(width: 3)
                .offset(x: -10)
        }
    }
}
