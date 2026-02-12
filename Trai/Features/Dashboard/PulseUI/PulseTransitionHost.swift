//
//  PulseTransitionHost.swift
//  Trai
//
//  Shared animation container for smooth in-place Pulse updates.
//

import SwiftUI

struct PulseTransitionHost<Content: View>: View {
    let id: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .id(id)
            .contentTransition(.opacity)
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: id)
    }
}
