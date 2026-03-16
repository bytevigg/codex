import Foundation

final class InteractionLimiter {
    private let maxPerHour: Int
    private let cooldownSeconds: Int
    private var history: [Date] = []

    init(maxPerHour: Int, cooldownSeconds: Int) {
        self.maxPerHour = maxPerHour
        self.cooldownSeconds = cooldownSeconds
    }

    func canInteract(now: Date = .now) -> Bool {
        trim(now: now)
        if let last = history.last, now.timeIntervalSince(last) < Double(cooldownSeconds) {
            return false
        }
        return history.count < maxPerHour
    }

    func record(now: Date = .now) {
        trim(now: now)
        history.append(now)
    }

    private func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-3600)
        history.removeAll { $0 < cutoff }
    }
}
