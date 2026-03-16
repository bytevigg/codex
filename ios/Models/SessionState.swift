import Foundation

enum SessionState: String, Sendable {
    case idle
    case triggered
    case paused
    case capturing
    case responding
    case resuming
}
