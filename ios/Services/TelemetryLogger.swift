import Foundation

struct TelemetryEvent: Codable {
    let name: String
    let payload: [String: String]
    let timestamp: String
}

final class TelemetryLogger {
    private let settings: AppSettings
    private let fileURL: URL

    init(settings: AppSettings) {
        self.settings = settings
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("telemetry_events.jsonl")
    }

    func emit(_ name: String, _ payload: [String: Any] = [:]) {
        guard settings.telemetry.enabled else { return }
        guard settings.telemetry.events.contains(name) else { return }

        // Convert payload values to strings for Codable simplicity
        let stringPayload = payload.mapValues { "\($0)" }

        let event = TelemetryEvent(
            name: name,
            payload: stringPayload,
            timestamp: ISO8601DateFormatter().string(from: .now)
        )

        guard let data = try? JSONEncoder().encode(event),
              let line = String(data: data, encoding: .utf8) else { return }

        let handle: FileHandle
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let h = try? FileHandle(forWritingTo: fileURL) else { return }
            h.seekToEndOfFile()
            handle = h
        } else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            guard let h = try? FileHandle(forWritingTo: fileURL) else { return }
            handle = h
        }

        handle.write((line + "\n").data(using: .utf8)!)
        handle.closeFile()
    }
}
