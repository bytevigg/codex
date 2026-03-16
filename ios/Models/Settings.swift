import Foundation
import Observation

@Observable
final class AppSettings: Codable {
    var enabled: Bool = true
    var wakePhrase: String = "hey youtube"
    var maxInteractionsPerHour: Int = 8
    var cooldownSeconds: Int = 45
    var activeHoursStart: Int = 7
    var activeHoursEnd: Int = 20
    var strictKidSafe: Bool = true
    var blockedTopics: [String] = ["violence", "politics", "religion", "scary"]
    var voice: String = "alloy"
    var character: CharacterSettings = .init()
    var protagonist: ProtagonistSettings = .init()
    var contentPolicy: ContentPolicySettings = .init()
    var retries: RetrySettings = .init()
    var telemetry: TelemetrySettings = .init()

    struct CharacterSettings: Codable {
        var maxSpokenSeconds: Int = 12
        var narrationPerson: String = "third_person"
        var strictPersona: Bool = true
        var voicePolicy: String = "style_inspired_distinct"
    }

    struct ProtagonistSettings: Codable {
        var preloadWindowSeconds: Int = 30
        var historyWindowSeconds: Int = 60
        var openWorld: Bool = true
        var acceptWakeOnlyWhenReady: Bool = true
        var minConfidence: Double = 0.45
    }

    struct ContentPolicySettings: Codable {
        var kidsOnly: Bool = true
    }

    struct RetrySettings: Codable {
        var pause: Int = 1
        var generation: Int = 1
    }

    struct TelemetrySettings: Codable {
        var enabled: Bool = true
        var events: [String] = [
            "wake_detected", "protagonist_confidence", "protagonist_ready",
            "pause_attempt", "response_start", "response_complete",
            "resume_success", "turn_outcome", "response_latency_ms", "latency_slo"
        ]
    }

    // MARK: - Persistence

    private static let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("settings.json")
    }()

    static func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            let defaults = AppSettings()
            defaults.save()
            return defaults
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Active hours check

    func withinActiveHours(_ date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= activeHoursStart && hour <= activeHoursEnd
    }

    // MARK: - Codable (manual because @Observable doesn't auto-synthesize)

    enum CodingKeys: String, CodingKey {
        case enabled, wakePhrase, maxInteractionsPerHour, cooldownSeconds
        case activeHoursStart, activeHoursEnd, strictKidSafe, blockedTopics
        case voice, character, protagonist, contentPolicy, retries, telemetry
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        wakePhrase = try c.decodeIfPresent(String.self, forKey: .wakePhrase) ?? "hey youtube"
        maxInteractionsPerHour = try c.decodeIfPresent(Int.self, forKey: .maxInteractionsPerHour) ?? 8
        cooldownSeconds = try c.decodeIfPresent(Int.self, forKey: .cooldownSeconds) ?? 45
        activeHoursStart = try c.decodeIfPresent(Int.self, forKey: .activeHoursStart) ?? 7
        activeHoursEnd = try c.decodeIfPresent(Int.self, forKey: .activeHoursEnd) ?? 20
        strictKidSafe = try c.decodeIfPresent(Bool.self, forKey: .strictKidSafe) ?? true
        blockedTopics = try c.decodeIfPresent([String].self, forKey: .blockedTopics) ?? ["violence", "politics", "religion", "scary"]
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? "alloy"
        character = try c.decodeIfPresent(CharacterSettings.self, forKey: .character) ?? .init()
        protagonist = try c.decodeIfPresent(ProtagonistSettings.self, forKey: .protagonist) ?? .init()
        contentPolicy = try c.decodeIfPresent(ContentPolicySettings.self, forKey: .contentPolicy) ?? .init()
        retries = try c.decodeIfPresent(RetrySettings.self, forKey: .retries) ?? .init()
        telemetry = try c.decodeIfPresent(TelemetrySettings.self, forKey: .telemetry) ?? .init()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(wakePhrase, forKey: .wakePhrase)
        try c.encode(maxInteractionsPerHour, forKey: .maxInteractionsPerHour)
        try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try c.encode(activeHoursStart, forKey: .activeHoursStart)
        try c.encode(activeHoursEnd, forKey: .activeHoursEnd)
        try c.encode(strictKidSafe, forKey: .strictKidSafe)
        try c.encode(blockedTopics, forKey: .blockedTopics)
        try c.encode(voice, forKey: .voice)
        try c.encode(character, forKey: .character)
        try c.encode(protagonist, forKey: .protagonist)
        try c.encode(contentPolicy, forKey: .contentPolicy)
        try c.encode(retries, forKey: .retries)
        try c.encode(telemetry, forKey: .telemetry)
    }
}
