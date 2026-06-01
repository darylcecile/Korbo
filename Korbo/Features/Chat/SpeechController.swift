import AVFoundation
import Speech
import SwiftUI

/// Manages TTS (read-aloud) and STT (dictation) for the chat interface.
@MainActor
final class SpeechController: NSObject, ObservableObject {
    static let shared = SpeechController()

    // MARK: TTS State

    @Published var speakingMessageID: String?
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: STT State

    @Published var isDictating = false
    @Published var partialTranscript = ""
    @Published var sttError: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: Init

    private override init() {
        super.init()
        synthesizer.delegate = self
        recognizer = SFSpeechRecognizer(locale: .current)
    }

    // MARK: TTS

    /// Toggles read-aloud for a given message. Stops if already speaking that message.
    func toggleSpeak(messageID: String, text: String) {
        if speakingMessageID == messageID {
            stopSpeaking()
            return
        }
        stopSpeaking()
        speakingMessageID = messageID

        configureAudioSession(for: .playback)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingMessageID = nil
    }

    // MARK: STT

    /// Requests permissions and starts live dictation, publishing partial transcripts.
    func startDictation() {
        guard !isDictating else { return }
        sttError = nil

        Task {
            // Request speech recognition permission
            let authStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }
            guard authStatus == .authorized else {
                sttError = "Speech recognition not authorized."
                return
            }

            // Request microphone permission (iOS 17+)
            let micGranted = await AVAudioApplication.requestRecordPermission()
            guard micGranted else {
                sttError = "Microphone access denied."
                return
            }

            beginRecognition()
        }
    }

    func stopDictation() {
        guard isDictating else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isDictating = false
    }

    private func beginRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            sttError = "Speech recognizer unavailable."
            return
        }

        configureAudioSession(for: .record)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            sttError = "Audio engine failed: \(error.localizedDescription)"
            return
        }

        isDictating = true
        partialTranscript = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopDictation()
                }
            }
        }
    }

    // MARK: Audio Session

    private func configureAudioSession(for mode: AudioMode) {
        let session = AVAudioSession.sharedInstance()
        do {
            switch mode {
            case .playback:
                try session.setCategory(.playback, mode: .default, options: [])
            case .record:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            }
            try session.setActive(true)
        } catch {
            // Best-effort; some simulators may fail
        }
    }

    private enum AudioMode { case playback, record }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
        }
    }
}
