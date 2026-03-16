import Foundation

/// Owns the end-to-end turn lifecycle: wake → pause → capture → respond → resume.
@MainActor
final class SessionOrchestrator: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var lastReply: String?
    @Published var statusMessage: String?

    let settings: AppSettings
    let youtube: YouTubePlayerBridge
    let wakeListener: WakeWordListener

    private let ai: AIClient
    private let telemetry: TelemetryLogger
    private let corrections: CorrectionStore
    private let protagonist: ProtagonistTracker
    private let limiter: InteractionLimiter
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()

    init(settings: AppSettings) {
        self.settings = settings
        self.youtube = YouTubePlayerBridge()
        self.wakeListener = WakeWordListener()

        self.ai = AIClient(settings: settings)
        self.telemetry = TelemetryLogger(settings: settings)
        self.corrections = CorrectionStore()
        self.protagonist = ProtagonistTracker(settings: settings, corrections: corrections)
        self.limiter = InteractionLimiter(
            maxPerHour: settings.maxInteractionsPerHour,
            cooldownSeconds: settings.cooldownSeconds
        )

        // Wire up wake phrase callback
        wakeListener.onWakePhrase = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleTrigger()
            }
        }
    }

    // MARK: - Start / Stop listening

    func startListening() async {
        let granted = await wakeListener.requestPermissions()
        if granted {
            wakeListener.startListening(wakePhrase: settings.wakePhrase)
            statusMessage = "Listening for \"\(settings.wakePhrase)\"..."
        } else {
            statusMessage = "Microphone or speech permission denied"
        }
    }

    func stopListening() {
        wakeListener.stopListening()
        statusMessage = nil
    }

    // MARK: - Protagonist warm-up

    func warmProtagonistState() async {
        let meta = await youtube.fetchMetadata()
        let now = Date.now
        let pState = protagonist.update(metadata: meta, transcriptHint: "", now: now)
        telemetry.emit("protagonist_confidence", [
            "video_id": pState.videoId,
            "ready": "\(pState.ready)",
            "confidence": "\(pState.candidate?.confidence ?? 0)"
        ])
    }

    // MARK: - Turn lifecycle

    func handleTrigger() async {
        let start = CFAbsoluteTimeGetCurrent()
        let now = Date.now

        telemetry.emit("wake_detected", ["video_id": "unknown"])

        // 1. Active hours check
        guard settings.withinActiveHours(now) else {
            statusMessage = "Outside active hours"
            return
        }

        // 2. Enabled check
        guard settings.enabled else {
            statusMessage = "Disabled by parent controls"
            return
        }

        // 3. Rate limit check
        guard limiter.canInteract(now: now) else {
            statusMessage = "Rate limit / cooldown active"
            return
        }

        state = .triggered

        // 4. Protagonist gate
        let meta = await youtube.fetchMetadata()
        let gateState = protagonist.update(metadata: meta, transcriptHint: "", now: now)
        telemetry.emit("protagonist_confidence", [
            "video_id": gateState.videoId,
            "ready": "\(gateState.ready)",
            "confidence": "\(gateState.candidate?.confidence ?? 0)"
        ])

        if settings.protagonist.acceptWakeOnlyWhenReady && !gateState.ready {
            statusMessage = "Protagonist not ready yet"
            state = .idle
            return
        }

        // 5. Pause YouTube with retry
        let paused = await pauseWithRetry()
        state = .paused
        if !paused {
            statusMessage = "Unable to control YouTube playback"
            state = .idle
            return
        }

        // From here: always resume in the end via explicit call
        let result = await performTurn(meta: meta, start: start)

        // Always resume + restart listener regardless of outcome
        await resumeAndCleanup()
        telemetry.emit("turn_outcome", ["success": "\(result)"])
    }

    /// Core turn logic after pause succeeds. Returns true on full success.
    private func performTurn(meta: VideoMetadata?, start: CFAbsoluteTimeInterval) async -> Bool {
        // 6. Capture child speech
        state = .capturing
        statusMessage = "Listening to your question..."

        let audioData: Data
        do {
            // Stop wake listener during capture to avoid feedback
            wakeListener.stopListening()
            audioData = try await recorder.record(seconds: 3)
        } catch {
            statusMessage = "I had trouble hearing you."
            return false
        }

        // 7. Transcribe
        let transcript: String
        do {
            transcript = try await ai.transcribe(audioData: audioData)
        } catch {
            statusMessage = "I had trouble understanding."
            return false
        }

        // 8. Check for correction
        if let correctedName = CorrectionStore.detectCorrection(in: transcript) {
            protagonist.applyCorrection(correctedName)
            telemetry.emit("protagonist_confidence", [
                "corrected_to": correctedName,
                "confidence": "0.95"
            ])
        }

        // 9. Update protagonist with transcript
        let updatedState = protagonist.update(metadata: meta, transcriptHint: transcript, now: Date.now)
        let protagonistName = updatedState.candidate?.name

        // 10. Generate reply with retry
        state = .responding
        statusMessage = "Thinking..."

        let rawReply = await generateWithRetry(
            transcript: transcript,
            screenshot: nil, // iOS: no screen capture needed, metadata suffices
            protagonistName: protagonistName
        )

        guard let reply = rawReply else {
            lastReply = "I had trouble answering right now."
            statusMessage = lastReply
            return false
        }

        let finalReply = ai.enforcePersonaContract(text: reply, protagonistName: protagonistName)
        lastReply = finalReply

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        telemetry.emit("response_latency_ms", ["latency_ms": "\(latencyMs)"])

        // 11. Speak
        statusMessage = "Speaking..."
        do {
            let ttsData = try await ai.speak(text: finalReply)
            try await player.play(data: ttsData)
            telemetry.emit("response_complete", ["duration_ms": "\(latencyMs)"])
        } catch {
            statusMessage = "I had trouble speaking right now."
            return false
        }

        return true
    }

    /// Always called after a turn attempt: resumes YouTube, restarts listener, resets state.
    private func resumeAndCleanup() async {
        state = .resuming
        let _ = await youtube.resume()
        telemetry.emit("resume_success", ["result": "true"])
        state = .idle
        limiter.record(now: Date.now)
        wakeListener.startListening(wakePhrase: settings.wakePhrase)
        statusMessage = "Listening for \"\(settings.wakePhrase)\"..."
    }

    // MARK: - Retry helpers

    private func pauseWithRetry() async -> Bool {
        let attempts = max(1, settings.retries.pause + 1)
        for i in 0..<attempts {
            let ok = await youtube.pause()
            telemetry.emit("pause_attempt", ["result": "\(ok)", "retries": "\(i)"])
            if ok { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func generateWithRetry(transcript: String, screenshot: Data?, protagonistName: String?) async -> String? {
        let attempts = max(1, settings.retries.generation + 1)
        for _ in 0..<attempts {
            do {
                return try await ai.generateReply(
                    userText: transcript,
                    screenshotPNG: screenshot,
                    protagonistName: protagonistName
                )
            } catch {
                continue
            }
        }
        return nil
    }
}
