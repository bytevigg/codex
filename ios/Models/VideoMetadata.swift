import Foundation

struct VideoMetadata {
    let videoId: String
    let title: String
    let channelName: String
    let description: String

    var seriesHint: String {
        let clean = title.trimmingCharacters(in: .whitespaces)
        if clean.contains(" - ") {
            return String(clean.split(separator: " - ", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
        }
        if clean.contains("|") {
            return String(clean.split(separator: "|", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
        }
        let words = clean.split(separator: " ").prefix(4)
        return words.joined(separator: " ")
    }

    static let empty = VideoMetadata(videoId: "", title: "", channelName: "", description: "")
}
