//
//  ChatDictationController.swift
//  Trai
//

import Combine
@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
final class ChatDictationController: ObservableObject {
    @Published var isRecording = false
    @Published var isPreparing = false

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var finalizedTranscript = ""
    private var volatileTranscript = ""
    private var updateText: ((String) -> Void)?

    func start(updateText: @escaping (String) -> Void) {
        guard !isRecording, !isPreparing else { return }

        self.finalizedTranscript = ""
        self.volatileTranscript = ""
        self.updateText = updateText
        isPreparing = true

        Task {
            do {
                try await startRecording()
                isPreparing = false
                isRecording = true
            } catch {
                isPreparing = false
                stop()
            }
        }
    }

    func stop() {
        guard isRecording || isPreparing || audioEngine != nil else { return }

        stopAudioInput()

        let analyzer = analyzer
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        analysisTask?.cancel()
        resultsTask?.cancel()
        resetSession()
    }

    func finish() async {
        guard isRecording || isPreparing || audioEngine != nil else { return }

        stopAudioInput()

        let analyzer = analyzer
        let resultsTask = resultsTask
        isRecording = false
        isPreparing = false

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        analysisTask?.cancel()
        resetSession()
    }

    private func stopAudioInput() {
        inputContinuation?.finish()
        inputContinuation = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func resetSession() {
        analysisTask = nil
        resultsTask = nil
        self.analyzer = nil
        finalizedTranscript = ""
        volatileTranscript = ""
        updateText = nil
        isRecording = false
        isPreparing = false
    }

    private func startRecording() async throws {
        try await requestPermissions()

        guard SpeechTranscriber.isAvailable else {
            throw ChatDictationError.unsupportedLocale
        }

        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en_US")
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]

        try await installAssetsIfNeeded(for: modules)

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: inputFormat
        ) ?? inputFormat

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )
        try await analyzer.prepareToAnalyze(in: analysisFormat)

        let inputStream = AsyncThrowingStream<AnalyzerInput, Error> { continuation in
            self.inputContinuation = continuation
        }

        let converter = inputFormat == analysisFormat ? nil : AVAudioConverter(from: inputFormat, to: analysisFormat)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let analyzerBuffer = Self.makeAnalyzerBuffer(
                from: buffer,
                outputFormat: analysisFormat,
                converter: converter
            ) else { return }

            Task { @MainActor in
                self?.inputContinuation?.yield(AnalyzerInput(buffer: analyzerBuffer))
            }
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        audioEngine.prepare()
        try audioEngine.start()

        self.audioEngine = audioEngine
        self.analyzer = analyzer

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                await MainActor.run {
                    self.stop()
                }
            }
        }

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    await MainActor.run {
                        self.apply(result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.stop()
                }
            }
        }
    }

    private func requestPermissions() async throws {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else { throw ChatDictationError.microphoneDenied }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { throw ChatDictationError.speechDenied }
    }

    private func installAssetsIfNeeded(for modules: [any SpeechModule]) async throws {
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            return
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        case .unsupported:
            throw ChatDictationError.unsupportedLocale
        @unknown default:
            throw ChatDictationError.unsupportedLocale
        }
    }

    private func apply(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if result.isFinal {
            finalizedTranscript = append(finalizedTranscript, text)
            volatileTranscript = ""
        } else {
            volatileTranscript = text
        }

        let spokenText = append(finalizedTranscript, volatileTranscript)
        updateText?(spokenText)
    }

    private func append(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }
        return lhs + " " + rhs
    }

    private static func makeAnalyzerBuffer(
        from buffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter?
    ) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else { return nil }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        switch status {
        case .haveData, .inputRanDry:
            return convertedBuffer
        case .error, .endOfStream:
            return nil
        @unknown default:
            return nil
        }
    }
}

private enum ChatDictationError: Error {
    case microphoneDenied
    case speechDenied
    case unsupportedLocale
}
