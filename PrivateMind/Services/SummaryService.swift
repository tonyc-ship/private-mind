import Foundation

final class SummaryService: @unchecked Sendable {
    static let shared = SummaryService()

    private init() {}

    // MARK: - Retry Logic
    /// Maximum number of retry attempts for network operations.
    private let maxRetryAttempts = 10
    /// Initial back-off delay (in seconds) between retries. This will double after each failed attempt.
    private let initialRetryDelay: TimeInterval = 1.0 // 1 second

    /// Executes the supplied async throwing operation with automatic retry.
    /// - Parameter operation: The async operation to perform.
    /// - Returns: The value returned by `operation` if it succeeds within the retry limit.
    /// - Throws: The last encountered error if all attempts fail.
    private func performWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var attempt = 0
        var delay = initialRetryDelay

        while true {
            // Log every attempt (starting from 1 so it  is human-readable).
            let currentAttempt = attempt + 1
            print("[Summary] performWithRetry attempt \(currentAttempt) / \(maxRetryAttempts)")

            do {
                let value = try await operation()

                // Only log success when we actually had to retry (attempt > 0). This keeps the logs concise.
                if attempt > 0 {
                    print("[Summary] operation succeeded on attempt \(currentAttempt)")
                }

                return value
            } catch {
                // Log the error and, if possible, retry.
                print("[Summary] attempt \(currentAttempt) failed with error: \(error.localizedDescription). Retry in \(delay) seconds.")

                attempt += 1
                if attempt >= maxRetryAttempts {
                    print("[Summary] giving up after \(currentAttempt) attempts")
                    throw error
                }

                // Exponential back-off before next attempt.
                try await Task.sleep(nanoseconds: UInt64(delay * Double(NSEC_PER_SEC)))
                delay = min(delay * 2, 8.0) // Cap delay to 8 seconds
            }
        }
    }

    /// Generates a meeting summary by calling the backend `/summarize` endpoint.
    /// - Parameters:
    ///   - transcript: Full transcript text.
    ///   - notes: User notes (may be empty).
    ///   - languageCode: Output language code (e.g. "en-US").
    ///   - template: Raw template markdown text (optional; default "Auto").
    /// - Returns: The summary text (markdown).
    func generateSummary(transcript: String,
                         notes: String,
                         languageCode: String,
                         template: String = "Auto") async throws -> String {
        return try await performWithRetry {
            try await self.generateSummaryOnce(transcript: transcript,
                                              notes: notes,
                                              languageCode: languageCode,
                                              template: template)
        }
    }

    /// Single-shot summary generation (internal). Use `generateSummary` for automatic retry.
    private func generateSummaryOnce(transcript: String,
                                     notes: String,
                                     languageCode: String,
                                     template: String = "Auto") async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let startTime = Date()
        print("[Summary] Starting summary generation. transcriptChars=\(transcript.count), notesChars=\(notes.count), lang=\(languageCode), template=\(template)")

        let content = """
        # User Notes:
        \(notes)

        # Transcript:
        \(transcript)

        # Output language code:
        \(languageCode)

        # Summary template:
        \(template)
        """

        let payload = [
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]

        let url = APIConfig.baseSummary.appendingPathComponent("summarize")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        var summary = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let token = line.dropFirst(6)
            summary += token.replacingOccurrences(of: "\\n", with: "\n")
        }
        let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Date().timeIntervalSince(startTime)
        print("[Summary] Finished summary generation. outputChars=\(finalSummary.count), duration=\(String(format: "%.2f", duration))s")

        return finalSummary
    }

    /// Generates a concise title for the meeting based on its summary.
    /// - Parameters:
    ///   - summary: The meeting summary text.
    ///   - languageCode: Output language code (e.g. "en-US").
    /// - Returns: A concise title (max 10 words).
    func generateTitle(summary: String, languageCode: String) async throws -> String {
        return try await performWithRetry {
            try await self.generateTitleOnce(summary: summary, languageCode: languageCode)
        }
    }

    /// Single-shot title generation (internal). Use `generateTitle` for automatic retry.
    private func generateTitleOnce(summary: String, languageCode: String) async throws -> String {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let startTime = Date()
        print("[Summary] Starting title generation. summaryChars=\(summary.count), lang=\(languageCode)")

        let content = """
        You are an expert meeting assistant that helps generate concise and descriptive meeting titles.

        # Meeting Summary:
        \(summary)

        # Language:
        \(languageCode)

        Based on the meeting summary above, generate a concise and descriptive title, Do not use any markdown format (maximum 10 words).
        The title should capture the main theme or purpose of the meeting.
        You MUST generate the title in the language specified by the language_code (e.g., \"en-US\" for English, \"zh-CN\" for Chinese, \"fr-FR\" for French, etc.).
        Do not include words like \"Meeting\", \"Summary\", or \"Notes\" in the title.
        """

        let payload = [
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]

        let url = APIConfig.baseSummary.appendingPathComponent("generate-title")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let title = (response?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let duration = Date().timeIntervalSince(startTime)
        print("[Summary] Finished title generation. titleChars=\(title.count), duration=\(String(format: "%.2f", duration))s")

        return title
    }
} 