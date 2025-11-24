//
//  LlamaState.swift
//  PrivateMind
//
//

import Foundation
import SwiftUI

@MainActor
class LlamaState: ObservableObject {
    private var llamaContext: LlamaContext?
    private var defaultModelUrl: URL? {
        // Try to find model in bundle or documents directory
        // let modelFileName: String = "gemma-1.1-2b-it.Q8_0"
        let modelFileName: String = "gemma-1.1-2b-it-Q4_K_M"
        return Bundle.main.url(forResource: modelFileName, withExtension: "gguf", subdirectory: "models")
            ?? getDocumentsDirectory().appendingPathComponent("\(modelFileName).gguf")
    }

    init() {
        // Model will be loaded lazily when needed
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    func loadModel(modelUrl: URL?) throws {
        let url = modelUrl ?? defaultModelUrl
        guard let url = url else {
            throw LlamaError.couldNotInitializeContext
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[LlamaState] Model file not found at: \(url.path)")
            throw LlamaError.couldNotInitializeContext
        }
        
        print("[LlamaState] Loading model from: \(url.path)")
        llamaContext = try LlamaContext.create_context(path: url.path())
        print("[LlamaState] Model loaded successfully")
    }

    func complete(text: String) async throws -> String {
        guard let llamaContext else {
            // Try to load model if not already loaded
            try loadModel(modelUrl: nil as URL?)
            guard let llamaContext = self.llamaContext else {
                throw LlamaError.couldNotInitializeContext
            }
            return try await completeWithContext(llamaContext: llamaContext, text: text, tokenCallback: nil as ((String) -> Void)?)
        }
        
        return try await completeWithContext(llamaContext: llamaContext, text: text, tokenCallback: nil as ((String) -> Void)?)
    }
    
    func complete(text: String, tokenCallback: ((String) -> Void)?) async throws -> String {
        guard let llamaContext else {
            // Try to load model if not already loaded
            try loadModel(modelUrl: nil)
            guard let llamaContext = self.llamaContext else {
                throw LlamaError.couldNotInitializeContext
            }
            return try await completeWithContext(llamaContext: llamaContext, text: text, tokenCallback: tokenCallback)
        }
        
        return try await completeWithContext(llamaContext: llamaContext, text: text, tokenCallback: tokenCallback)
    }
    
    private func completeWithContext(llamaContext: LlamaContext, text: String, tokenCallback: ((String) -> Void)?) async throws -> String {
        // Clear context before starting new completion
        await llamaContext.clear()
        await llamaContext.completion_init(text: text)
        
        let n_cur_initial = await llamaContext.n_cur
        let n_len = await llamaContext.n_len
        var result = ""
        var tokenCount = 0
        
        print("[LlamaState] Starting completion. n_cur_initial=\(n_cur_initial), n_len=\(n_len)")
        
        var current_n_cur = n_cur_initial
        while current_n_cur < n_len + n_cur_initial {
            let token = await llamaContext.completion_loop()
            tokenCount += 1
            
            if token.isEmpty {
                print("[LlamaState] Empty token received at iteration \(tokenCount), breaking")
                break
            }
            
            result += token
            print("[LlamaState] Token \(tokenCount): '\(token)' (result length now: \(result.count))")
            
            // Update current position
            current_n_cur = await llamaContext.n_cur
            
            // Call the callback on the main actor if provided
            if let tokenCallback = tokenCallback {
                await MainActor.run {
                    tokenCallback(token)
                }
            }
        }
        
        await llamaContext.clear()
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LlamaState] Completion finished. Token count: \(tokenCount), Raw result length: \(result.count), Trimmed length: \(trimmed.count)")
        return trimmed
    }

    func clear() async {
        guard let llamaContext else {
            return
        }
        await llamaContext.clear()
    }
}

