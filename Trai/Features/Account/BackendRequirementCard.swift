import SwiftUI

struct BackendRequirementCard: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: false, fillOpacity: 0.10))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TraiColors.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    BackendRequirementCard(
        message: "Local Development points at 127.0.0.1, so it only works in simulator-based testing.",
        actionTitle: "Use Staging"
    ) {}
    .padding()
}
