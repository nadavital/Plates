//
//  TraiSectionHeader.swift
//  Trai
//
//  Consistent section header with optional icon and trailing content.
//

import SwiftUI

struct TraiSectionHeader<Trailing: View>: View {
    let title: String
    var icon: String?
    var trailing: (() -> Trailing)?

    init(
        _ title: String,
        icon: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(TraiColors.flame)
            }

            Text(title)
                .font(.traiHeadline())

            Spacer()

            if let trailing {
                trailing()
            }
        }
    }
}

extension TraiSectionHeader where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
        self.trailing = nil
    }
}
