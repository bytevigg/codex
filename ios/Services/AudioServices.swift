import Foundation
import AVFoundation

/// Records a short audio clip from the microphone, returns WAV data.
final class AudioRecorder {
    private var recorder: AVAudioRecorder?

    func record(seconds: Double) async throws -> Data {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytbuddy-\(UUID().uuidString).wav")

        let formatSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        let rec = try AVAudioRecorder(url: tempURL, settings: formatSettings)
        rec.prepareToRecord()
        rec.record(forDuration: seconds)
        self.recorder = rec

        // Wait for recording to complete
        try await Task.sleep(for: .seconds(seconds + 0.1))
        rec.stop()
        self.recorder = nil

        defer {
            // Ephemeral: delete temp file after reading
            try? FileManager.default.removeItem(at: tempURL)
        }

        return try Data(contentsOf: tempURL)
    }
}

/// Plays audio data (AAC from TTS) using AVAudioPlayer.
final class AudioPlayer {
    private var player: AVAudioPlayer?

    func play(data: Data) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let player = try AVAudioPlayer(data: data)
        self.player = player
        player.prepareToPlay()
        player.play()

        // Wait for playback to finish
        while player.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
        }
        self.player = nil
    }
}
