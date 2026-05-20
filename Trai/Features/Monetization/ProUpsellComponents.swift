import SwiftUI

enum ProUpsellPresentationStyle {
    case sheet
    case fullScreenCover
}

struct ProUpsellRequest: Identifiable, Equatable {
    let id = UUID()
    let source: ProUpsellSource
    let style: ProUpsellPresentationStyle
}

@MainActor @Observable
final class ProUpsellCoordinator {
    static let shared = ProUpsellCoordinator()

    @ObservationIgnored
    private var presenterHandlers: [UUID: @MainActor (ProUpsellRequest?) -> Void] = [:]
    @ObservationIgnored
    private var presenterOrder: [UUID] = []
    @ObservationIgnored
    private(set) var activeRequest: ProUpsellRequest?

    func registerPresenter(
        id: UUID,
        handler: @escaping @MainActor (ProUpsellRequest?) -> Void
    ) {
        presenterHandlers[id] = handler
        activatePresenter(id: id)
        syncPresentation()
    }

    func activatePresenter(id: UUID) {
        presenterOrder.removeAll { $0 == id }
        presenterOrder.append(id)
        syncPresentation()
    }

    func unregisterPresenter(id: UUID) {
        presenterHandlers.removeValue(forKey: id)
        presenterOrder.removeAll { $0 == id }
        syncPresentation()
    }

    func present(
        source: ProUpsellSource,
        style: ProUpsellPresentationStyle = .sheet
    ) {
        activeRequest = ProUpsellRequest(source: source, style: style)
        syncPresentation()
    }

    func dismiss(requestID: UUID? = nil) {
        guard requestID == nil || activeRequest?.id == requestID else { return }
        activeRequest = nil
        syncPresentation()
    }

    private var activePresenterID: UUID? {
        presenterOrder.last(where: { presenterHandlers[$0] != nil })
    }

    private func syncPresentation() {
        let targetPresenterID = activePresenterID
        let request = activeRequest

        for (id, handler) in presenterHandlers {
            handler(id == targetPresenterID ? request : nil)
        }
    }
}

private struct ProUpsellPresenterModifier: ViewModifier {
    @Environment(ProUpsellCoordinator.self) private var proUpsellCoordinator: ProUpsellCoordinator?
    @State private var presenterID = UUID()
    @State private var activeRequest: ProUpsellRequest?

    func body(content: Content) -> some View {
        content
            .onAppear {
                proUpsellCoordinator?.registerPresenter(id: presenterID) { request in
                    activeRequest = request
                }
            }
            .onDisappear {
                proUpsellCoordinator?.unregisterPresenter(id: presenterID)
            }
            .sheet(item: sheetRequestBinding) { request in
                ProUpsellView(source: request.source)
                    .traiSheetBranding()
            }
            .fullScreenCover(item: fullScreenRequestBinding) { request in
                ProUpsellView(source: request.source)
                    .traiSheetBranding()
            }
    }

    private var sheetRequestBinding: Binding<ProUpsellRequest?> {
        Binding(
            get: {
                guard let request = activeRequest, request.style == .sheet else {
                    return nil
                }
                return request
            },
            set: { newValue in
                if let newValue {
                    activeRequest = newValue
                } else {
                    let dismissedRequestID = activeRequest?.id
                    activeRequest = nil
                    proUpsellCoordinator?.dismiss(requestID: dismissedRequestID)
                }
            }
        )
    }

    private var fullScreenRequestBinding: Binding<ProUpsellRequest?> {
        Binding(
            get: {
                guard let request = activeRequest, request.style == .fullScreenCover else {
                    return nil
                }
                return request
            },
            set: { newValue in
                if let newValue {
                    activeRequest = newValue
                } else {
                    let dismissedRequestID = activeRequest?.id
                    activeRequest = nil
                    proUpsellCoordinator?.dismiss(requestID: dismissedRequestID)
                }
            }
        )
    }
}

extension View {
    func proUpsellPresenter() -> some View {
        modifier(ProUpsellPresenterModifier())
    }
}

extension ProUpsellSource {
    var inlineTitle: String {
        offerContent.inlineTitle
    }

    var inlineMessage: String {
        offerContent.inlineMessage
    }

    var inlineSystemImage: String {
        offerContent.inlineIconName
    }
}

struct ProUpsellInlineCard: View {
    let source: ProUpsellSource
    var title: String? = nil
    var message: String? = nil
    var systemImage: String? = nil
    var actionTitle = "See Trai Pro"
    var isActionDisabled = false
    var showsActionButton = true
    var usesIconContainer = true
    let action: () -> Void

    var body: some View {
        Group {
            if showsActionButton {
                cardContent
            } else {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
                .disabled(isActionDisabled)
                .opacity(isActionDisabled ? 0.62 : 1)
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Trai Pro")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(TraiColors.brandAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.92), in: .capsule)

                        Spacer(minLength: 0)
                    }

                    Text(resolvedTitle)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)

                    Text(resolvedMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if showsActionButton {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TraiColors.brandAccent)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.92), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isActionDisabled)
                .opacity(isActionDisabled ? 0.62 : 1)
            } else {
                HStack(spacing: 8) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(16)
        .background(TraiColors.brandGradient, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: TraiColors.brandAccent.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        if usesIconContainer {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))

                Image(systemName: resolvedSystemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
        } else {
            Image(systemName: resolvedSystemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38)
        }
    }

    private var resolvedTitle: String {
        title ?? source.inlineTitle
    }

    private var resolvedMessage: String {
        message ?? source.inlineMessage
    }

    private var resolvedSystemImage: String {
        systemImage ?? "circle.hexagongrid.circle.fill"
    }
}
