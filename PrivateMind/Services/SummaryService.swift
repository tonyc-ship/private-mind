import Foundation
import SwiftUI

@MainActor
final class SummaryService: ObservableObject {
    static let shared = SummaryService()

    private var llamaState: LlamaState
    private var isModelLoaded = false

    private init() {
        self.llamaState = LlamaState()
    }
    
    /// Ensures the LLM model is loaded before use
    private func ensureModelLoaded() async throws {
        if !isModelLoaded {
            try llamaState.loadModel(modelUrl: nil as URL?)
            isModelLoaded = true
        }
    }

    /// Generates a meeting summary using local LLM inference.
    /// - Parameters:
    ///   - transcript: Full transcript text.
    ///   - notes: User notes (may be empty).
    ///   - languageCode: Output language code (e.g. "en-US").
    ///   - template: Raw template markdown text (optional; default "Auto").
    ///   - tokenCallback: Optional callback that receives each token as it's generated (for streaming).
    /// - Returns: The summary text (markdown).
    func generateSummary(transcript: String,
                         notes: String,
                         languageCode: String,
                         template: String = "Auto",
                         tokenCallback: ((String) -> Void)? = nil) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let startTime = Date()
        print("[Summary] Starting summary generation. transcriptChars=\(transcript.count), notesChars=\(notes.count), lang=\(languageCode), template=\(template)")

        try await ensureModelLoaded()

        // Build the prompt using ChatML format (standard for Qwen and many other models)
        // <|im_start|>system
        // {system_message}<|im_end|>
        // <|im_start|>user
        // {user_message}<|im_end|>
        // <|im_start|>assistant
        
        let systemPrompt = "You are a helpful and precise meeting assistant. Your task is to summarize the provided meeting transcript."
        
        var userPrompt = ""
        if !notes.isEmpty {
            userPrompt += "User Notes:\n\(notes)\n\n"
        }
        userPrompt += "Transcript:\n\(transcript)\n\n"
        userPrompt += "Please provide a structured summary in \(languageCode). Focus on key points, decisions, and action items. Be concise."
        
        if template != "Auto" && !template.isEmpty {
            userPrompt += "\n\nUse this format:\n\(template)"
        }
        
        let prompt = """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(userPrompt)<|im_end|>
        <|im_start|>assistant
        
        """
        
        print("[Summary] Prompt: \(prompt)")

        let (summary, tokenCount) = try await llamaState.complete(text: prompt, tokenCallback: tokenCallback)
        let duration = Date().timeIntervalSince(startTime)
        let tokensPerSecond = duration > 0 ? Double(tokenCount) / duration : 0.0
        print("[Summary] Finished summary generation. outputChars=\(summary.count), duration=\(String(format: "%.2f", duration))s, tokens=\(tokenCount), tokens/s=\(String(format: "%.2f", tokensPerSecond))")

        return summary
    }

    /// Generates a concise title for the meeting based on its summary using local LLM inference.
    /// - Parameters:
    ///   - summary: The meeting summary text.
    ///   - languageCode: Output language code (e.g. "en-US").
    ///   - tokenCallback: Optional callback that receives each token as it's generated (for streaming).
    /// - Returns: A concise title (max 10 words).
    func generateTitle(summary: String, languageCode: String, tokenCallback: ((String) -> Void)? = nil) async throws -> String {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let startTime = Date()
        print("[Summary] Starting title generation. summaryChars=\(summary.count), lang=\(languageCode)")

        try await ensureModelLoaded()
        
        // Use ChatML format for title generation as well
        // Truncate summary if too long to avoid context issues and distraction
        let truncatedSummary = summary.count > 1000 ? String(summary.prefix(1000)) + "..." : summary
        
        let prompt = """
        <|im_start|>system
        You are a helpful assistant. Generate a short, descriptive title for the meeting.<|im_end|>
        <|im_start|>user
        Based on the following summary, generate a concise meeting title (max 10 words). Do not use quotes.
        
        Summary:
        \(truncatedSummary)
        
        Language: \(languageCode)<|im_end|>
        <|im_start|>assistant
        Title: 
        """

        let (title, tokenCount) = try await llamaState.complete(text: prompt, tokenCallback: tokenCallback)
        let cleanTitle = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let duration = Date().timeIntervalSince(startTime)
        let tokensPerSecond = duration > 0 ? Double(tokenCount) / duration : 0.0
        print("[Summary] Finished title generation. Raw title: '\(title)', Clean title: '\(cleanTitle)', titleChars=\(cleanTitle.count), duration=\(String(format: "%.2f", duration))s, tokens=\(tokenCount), tokens/s=\(String(format: "%.2f", tokensPerSecond))")

        return cleanTitle
    }
} 