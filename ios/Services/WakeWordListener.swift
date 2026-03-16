import Foundation
import Speech
import AVFoundation

/// Continuously listens for the wake phrase using on-device speech recognition.
@MainActor
final class WakeWordListener: ObservableObject {
    @Published var isListening = false
    @Published var lastTranscript = ""
    @Published var permissionGranted = false

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var onWakePhrase: (() -> Void)?
    private var wakePhrase = "hey youtube"

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            permissionGranted = false
            return false
        }

        let audioStatus: Bool
        if #available(iOS 17.0, *) {
            audioStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            audioStatus = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }

        permissionGranted = audioStatus
        return audioStatus
    }

    func startListening(wakePhrase: String) {
        self.wakePhrase = wakePhrase.lowercased()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[WakeWordListener] Speech recognizer unavailable")
            return
        }

        // Stop any existing session
        stopListening()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[WakeWordListener] Audio session error: \(error)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        if #available(iOS 17.0, *) {
            request.addsPunctuation = false
        }
        // Prefer on-device recognition for lower latency
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                Task { @MainActor in
                    self.lastTranscript = text
                    if text.contains(self.wakePhrase) {
                        self.onWakePhrase?()
                        // Restart after trigger to reset transcript buffer
                        self.restartListening()
                    }
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                // Recognition ended (timeout, error, etc.) — restart
                Task { @MainActor in
                    self.restartListening()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            print("[WakeWordListener] Audio engine failed to start: \(error)")
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    /// After a wake detection or recognition timeout, restart the listener.
    func restartListening() {
        stopListening()
        // Small delay before restarting to avoid rapid cycling
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            startListening(wakePhrase: wakePhrase)
        }
    }
}
