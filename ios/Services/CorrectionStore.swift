import Foundation

final class CorrectionStore {
    private let fileURL: URL
    private var data: [String: Double]

    private static let correctionPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bthat(?:'s| is)\s+([a-zA-Z][\w\- ]{1,40})"#,
            #"\bit(?:'s| is)\s+([a-zA-Z][\w\- ]{1,40})"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("protagonist_corrections.json")
        self.data = Self.load(from: fileURL)
    }

    func boost(key: String, amount: Double = 0.15) {
        data[key] = (data[key] ?? 0.0) + amount
        save()
    }

    func score(for key: String) -> Double {
        data[key] ?? 0.0
    }

    // MARK: - Static correction detection

    static func detectCorrection(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for pattern in correctionPatterns {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = pattern.firstMatch(in: trimmed, range: range),
               let captureRange = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[captureRange])
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: ".,!?")))
            }
        }
        return nil
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> [String: Double] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
