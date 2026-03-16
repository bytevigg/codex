import Foundation

/// Direct OpenAI API client using URLSession.
final class AIClient: Sendable {
    // MARK: - PROTOTYPE ONLY: Replace with secure storage before shipping
    private static let apiKey = "YOUR_OPENAI_API_KEY_HERE"
    private let baseURL = "https://api.openai.com/v1"

    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings) {
        self.settings = settings
        self.session = URLSession.shared
    }

    // MARK: - Transcription (for child's question after wake)

    func transcribe(audioData: Data) async throws -> String {
        let boundary = UUID().uuidString
        var request = makeRequest(path: "/audio/transcriptions", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        let (data, _) = try await session.data(for: request)

        struct TranscriptionResponse: Decodable { let text: String }
        let resp = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chat generation (multimodal with screenshot)

    func generateReply(
        userText: String,
        screenshotPNG: Data?,
        protagonistName: String?
    ) async throws -> String {
        let persona = protagonistName ?? "The character"
        let systemPrompt = """
        You are a playful character companion for young kids.
        Follow these rules strictly:
        - Keep response kid-safe and warm.
        - Avoid blocked topics and redirect gently.
        - Never mention violence, fear, medical, politics, religion, or adult content.
        - Keep to 1-2 short sentences and around 10 seconds spoken.
        - End naturally (no trailing unfinished phrase).
        """

        let userPrompt = """
        Child said: "\(userText)"
        Blocked topics: \(settings.blockedTopics.joined(separator: ", "))
        Protagonist candidate: \(persona)
        Respond strictly in third-person (e.g. '\(persona) says ...').
        """

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Build user message content (text + optional image)
        var content: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]

        if let png = screenshotPNG {
            let b64 = png.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/png;base64,\(b64)"]
            ])
        }

        messages.append(["role": "user", "content": content])

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 90
        ]

        var request = makeRequest(path: "/chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct ChatResponse: Decodable { let choices: [Choice] }

        let resp = try JSONDecoder().decode(ChatResponse.self, from: data)
        return resp.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Let's keep having fun and learning together!"
    }

    // MARK: - Persona enforcement

    func enforcePersonaContract(text: String, protagonistName: String?) -> String {
        let safeName = (protagonistName ?? "The character").trimmingCharacters(in: .whitespaces)
        var normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Strip leading first-person
        if normalized.lowercased().hasPrefix("i ") {
            normalized = String(normalized.dropFirst(2)).capitalized
        }
        normalized = normalized
            .replacingOccurrences(of: " I ", with: " they ")
            .replacingOccurrences(of: " I'm ", with: " they are ")

        // Ensure third-person prefix
        let lower = normalized.lowercased()
        if !lower.contains(" says ") && !lower.hasPrefix("\(safeName.lowercased()) says") {
            normalized = "\(safeName) says \(normalized)"
        }

        // Truncate to max word budget
        let maxWords = max(10, settings.character.maxSpokenSeconds * 3)
        let words = normalized.split(separator: " ")
        if words.count > maxWords {
            normalized = words.prefix(maxWords).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,")) + "."
        }

        return normalized
    }

    // MARK: - TTS

    func speak(text: String) async throws -> Data {
        let body: [String: Any] = [
            "model": "tts-1",
            "voice": settings.voice,
            "input": text,
            "response_format": "aac"
        ]

        var request = makeRequest(path: "/audio/speech", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }
}

// MARK: - Multipart helper

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
