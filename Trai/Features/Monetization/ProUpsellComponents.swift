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
                    .tint(TraiColors.brandAccent)
                    .accentColor(TraiColors.brandAccent)
            }
            .fullScreenCover(item: fullScreenRequestBinding) { request in
                ProUpsellView(source: request.source)
                    .tint(TraiColors.brandAccent)
                    .accentColor(TraiColors.brandAccent)
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
        switch self {
        case .chat:
            "Unlock coach chat"
        case .foodAnalysis:
            "Unlock AI food logging"
        case .nutritionPlan:
            "Unlock AI plan coaching"
        case .workoutPlan:
            "Unlock workout coaching"
        case .exerciseAnalysis:
            "Unlock exercise analysis"
        case .settings:
            "Upgrade to Trai Pro"
        }
    }

    var inlineMessage: String {
        switch self {
        case .chat:
            "Talk with Trai about food, workouts, momentum, and next steps in one ongoing conversation."
        case .foodAnalysis:
            "Snap meals and get fast calorie and macro estimates when you want the quickest path to logging."
        case .nutritionPlan:
            "Review and refine your nutrition plan with coaching that adapts to your goals and routine."
        case .workoutPlan:
            "Build and refine workout plans around your schedule, goals, and available equipment."
        case .exerciseAnalysis:
            "Get instant exercise guidance, smarter setup help, and faster analysis when adding new movements."
        case .settings:
            "Unlock adaptive coaching, faster food logging, and personalized plans across the app."
        }
    }

    var inlineSystemImage: String {
        switch self {
        case .chat:
            "message.badge.waveform.fill"
        case .foodAnalysis:
            "fork.knife"
        case .nutritionPlan:
            "slider.horizontal.3"
        case .workoutPlan:
            "figure.strengthtraining.traditional"
        case .exerciseAnalysis:
            "dumbbell.fill"
        case .settings:
            "circle.hexagongrid.circle"
        }
    }
}

struct ProUpsellInlineCard: View {
    let source: ProUpsellSource
    var actionTitle = "See Trai Pro"
    var isActionDisabled = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source.inlineSystemImage)
                    .font(.headline)
                    .foregroundStyle(TraiColors.brandAccent)
                    .frame(width: 36, height: 36)
                    .background(
                        TraiColors.brandAccent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.inlineTitle)
                        .font(.traiHeadline(18))

                    Text(source.inlineMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.traiSecondary(color: TraiColors.brandAccent, fullWidth: true, fillOpacity: 0.12))
            .disabled(isActionDisabled)
        }
    }
}
