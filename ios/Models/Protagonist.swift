import Foundation

struct ProtagonistCandidate {
    let name: String
    var confidence: Double
    var sourceMix: [String]
}

struct ProtagonistState {
    let videoId: String
    var ready: Bool
    var candidate: ProtagonistCandidate?
    let startedAt: Date
}

final class ProtagonistTracker {
    private let settings: AppSettings
    private let corrections: CorrectionStore
    private var currentState: ProtagonistState?

    private static let namePattern = try! NSRegularExpression(
        pattern: #"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b"#
    )

    init(settings: AppSettings, corrections: CorrectionStore) {
        self.settings = settings
        self.corrections = corrections
    }

    var state: ProtagonistState? { currentState }

    /// Derive a pseudo video-id from page title (since we don't have frame hashing on iOS).
    private func videoId(from metadata: VideoMetadata?) -> String {
        guard let meta = metadata, !meta.videoId.isEmpty else {
            return "unknown-\(UUID().uuidString.prefix(8))"
        }
        return meta.videoId
    }

    func ensureState(metadata: VideoMetadata?, now: Date) -> ProtagonistState {
        let vid = videoId(from: metadata)
        if let existing = currentState, existing.videoId == vid {
            return existing
        }
        let fresh = ProtagonistState(videoId: vid, ready: false, candidate: nil, startedAt: now)
        currentState = fresh
        return fresh
    }

    @discardableResult
    func update(metadata: VideoMetadata?, transcriptHint: String, now: Date) -> ProtagonistState {
        var state = ensureState(metadata: metadata, now: now)

        // Build hint text from metadata + transcript
        var hints = transcriptHint
        if let meta = metadata {
            hints += " " + meta.title + " " + meta.channelName
        }

        let candidate = inferCandidate(videoId: state.videoId, text: hints)
        let preload = TimeInterval(settings.protagonist.preloadWindowSeconds)
        let age = now.timeIntervalSince(state.startedAt)

        let ready: Bool
        if let c = candidate {
            ready = c.confidence >= settings.protagonist.minConfidence || age >= preload
        } else {
            ready = age >= preload  // After preload window, proceed even without candidate
        }

        state.ready = ready
        state.candidate = candidate
        currentState = state
        return state
    }

    func applyCorrection(_ name: String) {
        guard var state = currentState else { return }
        let key = correctionKey(videoId: state.videoId, name: name)
        corrections.boost(key: key)
        state.candidate = ProtagonistCandidate(
            name: name,
            confidence: 0.95,
            sourceMix: ["user_correction"]
        )
        state.ready = true
        currentState = state
    }

    // MARK: - Private

    private func correctionKey(videoId: String, name: String) -> String {
        "\(videoId):\(name.lowercased())"
    }

    private func inferCandidate(videoId: String, text: String) -> ProtagonistCandidate? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = Self.namePattern.matches(in: text, range: range)
        let names = matches.compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
        guard !names.isEmpty else { return nil }

        let winner = names.max(by: { $0.count < $1.count })!
        let key = correctionKey(videoId: videoId, name: winner)
        let baseConfidence = min(0.8, 0.35 + Double(winner.count) / 24.0)
        let boosted = min(0.99, baseConfidence + corrections.score(for: key))

        return ProtagonistCandidate(
            name: winner,
            confidence: boosted,
            sourceMix: ["transcript"]
        )
    }
}
