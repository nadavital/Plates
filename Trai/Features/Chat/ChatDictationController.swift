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
    private var emittedTranscript = ""
    private var updateText: ((String) -> Void)?

    func start(updateText: @escaping (String) -> Void) {
        guard !isRecording, !isPreparing else { return }

        self.finalizedTranscript = ""
        self.volatileTranscript = ""
        self.emittedTranscript = ""
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

        inputContinuation?.finish()
        inputContinuation = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        let analyzer = analyzer
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        analysisTask?.cancel()
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        self.analyzer = nil
        finalizedTranscript = ""
        volatileTranscript = ""
        emittedTranscript = ""
        updateText = nil
        isRecording = false
        isPreparing = false
    }

    private func startRecording() async throws {
        try await requestPermissions()

        let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en_US")
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
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

    private func apply(_ result: DictationTranscriber.Result) {
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
        let delta = incrementalText(from: emittedTranscript, to: spokenText)
        emittedTranscript = spokenText

        guard !delta.isEmpty else { return }
        updateText?(delta)
    }

    private func append(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }
        return lhs + " " + rhs
    }

    private func incrementalText(from previous: String, to current: String) -> String {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return "" }
        guard !previous.isEmpty else { return current }

        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var previousIndex = previous.startIndex
        var currentIndex = current.startIndex
        while previousIndex < previous.endIndex,
              currentIndex < current.endIndex,
              previous[previousIndex] == current[currentIndex] {
            previousIndex = previous.index(after: previousIndex)
            currentIndex = current.index(after: currentIndex)
        }

        return String(current[currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
