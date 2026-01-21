//
//  ChatCameraComponents.swift
//  Trai
//
//  Camera view and image preview for chat
//

import SwiftUI
import AVFoundation

// MARK: - Chat Camera View

struct ChatCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    @State private var cameraService = ChatCameraService()

    var body: some View {
        NavigationStack {
            ZStack {
                ChatCameraPreview(cameraService: cameraService)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    Button {
                        Task {
                            if let image = await cameraService.capturePhoto() {
                                HapticManager.mediumTap()
                                onCapture(image)
                                dismiss()
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .task {
                await cameraService.requestPermission()
            }
        }
    }
}

// MARK: - Chat Camera Preview

private struct ChatCameraPreview: UIViewRepresentable {
    let cameraService: ChatCameraService

    func makeUIView(context: Context) -> ChatCameraPreviewUIView {
        let view = ChatCameraPreviewUIView()
        view.backgroundColor = .black
        cameraService.setupPreviewLayer(in: view)
        return view
    }

    func updateUIView(_ uiView: ChatCameraPreviewUIView, context: Context) {
        uiView.updatePreviewFrame()
    }
}

private class ChatCameraPreviewUIView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewFrame()
    }

    func updatePreviewFrame() {
        layer.sublayers?.forEach { sublayer in
            if sublayer is AVCaptureVideoPreviewLayer {
                sublayer.frame = bounds
            }
        }
    }
}

// MARK: - Chat Camera Service

@Observable
@MainActor
final class ChatCameraService: NSObject {
    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    var isAuthorized = false

    func requestPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            isAuthorized = true
            await setupCamera()
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            if isAuthorized {
                await setupCamera()
            }
        default:
            isAuthorized = false
        }
    }

    private func setupCamera() async {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        Task.detached { [captureSession] in
            captureSession.startRunning()
        }
    }

    func setupPreviewLayer(in view: UIView) {
        previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.connection?.videoOrientation = .portrait

        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension ChatCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                photoContinuation?.resume(returning: nil)
                photoContinuation = nil
                return
            }

            photoContinuation?.resume(returning: image)
            photoContinuation = nil
        }
    }
}

// MARK: - Image Preview View

struct ImagePreviewView: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.spring) {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            }
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        onDismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}
