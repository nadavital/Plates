//
//  CameraService.swift
//  Trai
//
//  Camera capture service and preview components
//

import SwiftUI
import AVFoundation

func foodCameraDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[FoodCamera] \(message())")
#endif
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.cameraService = cameraService
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.cameraService = cameraService
        uiView.updatePreviewFrame()
    }
}

/// Custom UIView that updates preview layer frame on layout
class CameraPreviewUIView: UIView {
    weak var cameraService: CameraService?
    private var hasAttachedPreviewLayer = false

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraPreviewUIView must be backed by AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachPreviewLayerIfNeeded()
        updatePreviewFrame()
    }

    func updatePreviewFrame() {
        previewLayer.frame = bounds
    }

    private func attachPreviewLayerIfNeeded() {
        guard !hasAttachedPreviewLayer else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        cameraService?.setupPreviewLayer(in: self)
        hasAttachedPreviewLayer = true
    }
}

// MARK: - Camera Service

@Observable
@MainActor
final class CameraService: NSObject {
    private static let idleShutdownNanoseconds: UInt64 = 15_000_000_000
    private static let previewFrameTimeoutNanoseconds: UInt64 = 1_500_000_000

    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.nadav.trai.food-camera.preview")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    private var isConfigured = false
    private var startSessionTask: Task<Bool, Never>?
    private var idleShutdownTask: Task<Void, Never>?
    private var hasReceivedPreviewFrame = false

    var isAuthorized = false
    var isSessionReady = false

    func preparePipelineIfAuthorized() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        isAuthorized = true
        cancelIdleShutdown()
        foodCameraDebugLog("preparePipelineIfAuthorized")
        _ = configureSessionIfNeeded()
    }

    func prewarmIfAuthorized() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        isAuthorized = true
        cancelIdleShutdown()

        Task { @MainActor in
            await ensureSessionRunning()
        }
    }

    func prepareForPresentationIfAuthorized() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        isAuthorized = true
        foodCameraDebugLog("prepareForPresentationIfAuthorized")
        await ensureSessionRunning()
    }

    func requestPermission() async {
        cancelIdleShutdown()
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        foodCameraDebugLog("requestPermission status=\(String(describing: status.rawValue))")

        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }

        guard isAuthorized else {
            foodCameraDebugLog("requestPermission denied")
            stopSession()
            return
        }

        foodCameraDebugLog("requestPermission granted")
        await ensureSessionRunning()
    }

    private func configureSessionIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        foodCameraDebugLog("configureSessionIfNeeded begin")

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return false
        }

        let hasVideoInput = captureSession.inputs.contains { sessionInput in
            guard let videoInput = sessionInput as? AVCaptureDeviceInput else { return false }
            return videoInput.device.hasMediaType(.video)
        }
        if !hasVideoInput {
            guard captureSession.canAddInput(input) else { return false }
            captureSession.addInput(input)
        }

        let hasPhotoOutput = captureSession.outputs.contains { output in
            output === photoOutput
        }
        if !hasPhotoOutput {
            guard captureSession.canAddOutput(photoOutput) else { return false }
            captureSession.addOutput(photoOutput)
        }

        let hasVideoOutput = captureSession.outputs.contains { output in
            output === videoOutput
        }
        if !hasVideoOutput {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            guard captureSession.canAddOutput(videoOutput) else { return false }
            captureSession.addOutput(videoOutput)
        }

        isConfigured = true
        foodCameraDebugLog("configureSessionIfNeeded success")
        return true
    }

    private func ensureSessionRunning() async {
        cancelIdleShutdown()
        foodCameraDebugLog("ensureSessionRunning begin configured=\(isConfigured) running=\(captureSession.isRunning)")

        guard configureSessionIfNeeded() else {
            isSessionReady = false
            foodCameraDebugLog("ensureSessionRunning configure failed")
            return
        }

        if captureSession.isRunning {
            let previewReady = await waitForPreviewFrameIfNeeded()
            isSessionReady = previewReady
            foodCameraDebugLog("ensureSessionRunning already running previewReady=\(previewReady)")
            return
        }

        if let existingStartTask = startSessionTask {
            isSessionReady = await existingStartTask.value
            foodCameraDebugLog("ensureSessionRunning awaited existing task ready=\(isSessionReady)")
            return
        }

        let session = captureSession
        let task = Task.detached(priority: .userInitiated) { () -> Bool in
            if !session.isRunning {
                session.startRunning()
            }
            return session.isRunning
        }
        startSessionTask = task

        let didStart = await task.value
        startSessionTask = nil
        guard didStart else {
            isSessionReady = false
            foodCameraDebugLog("ensureSessionRunning finished ready=false")
            return
        }

        let previewReady = await waitForPreviewFrameIfNeeded()
        isSessionReady = previewReady
        foodCameraDebugLog("ensureSessionRunning finished previewReady=\(previewReady)")
    }

    func setupPreviewLayer(in view: CameraPreviewUIView) {
        let layer = view.previewLayer
        foodCameraDebugLog("setupPreviewLayer bounds=\(view.bounds.debugDescription)")

        if layer.session !== captureSession {
            layer.session = captureSession
        }
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.connection?.videoRotationAngle = 90

        previewLayer = layer
    }

    func capturePhoto() async -> UIImage? {
        guard isAuthorized else { return nil }

        if !isSessionReady || !captureSession.isRunning {
            await ensureSessionRunning()
        }
        guard isSessionReady else { return nil }
        guard photoContinuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stopSession() {
        cancelIdleShutdown()
        startSessionTask?.cancel()
        startSessionTask = nil
        foodCameraDebugLog("stopSession running=\(captureSession.isRunning)")
        hasReceivedPreviewFrame = false

        guard captureSession.isRunning else {
            isSessionReady = false
            return
        }

        let session = captureSession
        Task.detached(priority: .utility) {
            session.stopRunning()
        }

        isSessionReady = false
    }

    private func waitForPreviewFrameIfNeeded() async -> Bool {
        if hasReceivedPreviewFrame {
            return true
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + Self.previewFrameTimeoutNanoseconds
        while !hasReceivedPreviewFrame && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        return hasReceivedPreviewFrame
    }

    func scheduleIdleShutdown() {
        idleShutdownTask?.cancel()
        guard captureSession.isRunning || startSessionTask != nil else { return }
        foodCameraDebugLog("scheduleIdleShutdown")

        idleShutdownTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.idleShutdownNanoseconds)
            } catch {
                return
            }

            guard let self else { return }
            self.stopSession()
            self.idleShutdownTask = nil
        }
    }

    private func cancelIdleShutdown() {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if error != nil {
                photoContinuation?.resume(returning: nil)
                photoContinuation = nil
                return
            }

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

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            guard !hasReceivedPreviewFrame else { return }
            hasReceivedPreviewFrame = true
            isSessionReady = true
            foodCameraDebugLog("firstPreviewFrameReceived")
        }
    }
}
