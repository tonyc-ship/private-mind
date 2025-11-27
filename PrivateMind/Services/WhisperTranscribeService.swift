import Foundation
import AVFoundation
import Combine
import UIKit

/// Service that uses Whisper model for on-device transcription.
/// This provides an alternative to the WebSocket-based transcription service.
@MainActor
final class WhisperTranscribeService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    // MARK: - Published values
    @Published var isStreaming = false
    @Published var isPaused = false
    @Published var displayText: String = ""
    
    // MARK: - Private properties
    private var whisperContext: WhisperContext?
    private let recorder = WhisperRecorder()
    private var recordedFile: URL?
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }
    
    // Track accumulated transcription text
    private var accumulatedText: String = ""
    private var lastTranscribedText: String = ""
    private var lastTranscriptionTime: Date = Date()
    private var lastProcessedSegmentCount: Int = 0
    
    private var currentLanguageCode: String = "en-US"
    private var modelUrl: URL? {
        // Try resources/whisper subdirectory first, then fall back to root
        Bundle.main.url(forResource: "ggml-base", withExtension: "bin", subdirectory: "resources/whisper")
            ?? Bundle.main.url(forResource: "ggml-base", withExtension: "bin")
    }
    
    private var transcriptionTask: Task<Void, Never>?
    private var isModelLoaded = false
    private var isInBackground = false
    nonisolated(unsafe) private var backgroundObservers: [NSObjectProtocol] = []
    
    override init() {
        super.init()
        setupBackgroundObservers()
    }
    
    deinit {
        // Remove observers synchronously - NotificationCenter.removeObserver is thread-safe
        backgroundObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Public API
    /// Starts recording and transcribing with Whisper.
    func start(languageCode: String = "en-US", email: String = "") async {
        guard !isStreaming else { return }
        
        currentLanguageCode = languageCode
        displayText = ""
        accumulatedText = ""
        lastTranscribedText = ""
        lastTranscriptionTime = Date()
        lastProcessedSegmentCount = 0
        
        do {
            try configureAudioSession()
            
            // Start recording
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("whisper-recording-\(UUID().uuidString).wav")
            try await recorder.startRecording(toOutputFile: file, delegate: self)
            recordedFile = file
            isStreaming = true
            isPaused = false
            
            // Load model in background
            // Use GPU if not in background, CPU if backgrounded
            Task {
                await loadModel(useGPU: !isInBackground)
            }
            
            // Start periodic transcription
            startPeriodicTranscription()
        } catch {
            print("[WhisperTranscribe] Failed to start: \(error)")
            cleanup()
        }
    }
    
    func stop(deactivateAudioSession: Bool = true) {
        guard isStreaming else { return }
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        Task {
            await recorder.stopRecording()
            
            // Final transcription
            if let file = recordedFile {
                await performFinalTranscription(file: file)
            }
            
            await MainActor.run {
                cleanup(deactivateAudioSession: deactivateAudioSession)
            }
        }
    }
    
    func pause() {
        guard isStreaming, !isPaused else { return }
        Task {
            await recorder.stopRecording()
            isPaused = true
        }
    }
    
    func resume() {
        guard isStreaming, isPaused else { return }
        Task {
            do {
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("whisper-recording-\(UUID().uuidString).wav")
                try await recorder.startRecording(toOutputFile: file, delegate: self)
                await MainActor.run {
                    recordedFile = file
                    // Reset segment count since we're starting a new file
                    // but keep accumulatedText to continue the transcript
                    lastProcessedSegmentCount = 0
                    isPaused = false
                    startPeriodicTranscription()
                }
            } catch {
                print("[WhisperTranscribe] Failed to resume: \(error)")
            }
        }
    }
    
    // MARK: - Private helpers
    private func configureAudioSession() throws {
        // Configure for background audio recording
        // .defaultToSpeaker ensures audio continues when screen is locked
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func setupBackgroundObservers() {
        let center = NotificationCenter.default
        
        // Observe when app enters background
        let willResignActive = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppBackground()
            }
        }
        
        // Observe when app enters foreground
        let didBecomeActive = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppForeground()
            }
        }
        
        backgroundObservers = [willResignActive, didBecomeActive]
    }
    
    
    private func handleAppBackground() {
        isInBackground = true
        print("[WhisperTranscribe] App entered background - reloading model with CPU-only mode")
        
        // Reload model with CPU-only mode (Metal cannot be used in background)
        Task {
            // Free old context
            whisperContext = nil
            isModelLoaded = false
            
            // Reload with CPU-only
            await loadModel(useGPU: false)
        }
    }
    
    private func handleAppForeground() {
        isInBackground = false
        print("[WhisperTranscribe] App entered foreground - reloading model with GPU support")
        
        // Reload model with GPU support when back in foreground
        Task {
            // Free old context
            whisperContext = nil
            isModelLoaded = false
            
            // Reload with GPU
            await loadModel(useGPU: true)
        }
    }
    
    private func loadModel(useGPU: Bool = true) async {
        // If already loaded with the correct GPU setting, don't reload
        if isModelLoaded && whisperContext != nil {
            return
        }
        
        guard let modelUrl else {
            print("[WhisperTranscribe] Whisper model not found in bundle")
            return
        }
        
        do {
            whisperContext = try WhisperContext.createContext(path: modelUrl.path(), useGPU: useGPU)
            isModelLoaded = true
            print("[WhisperTranscribe] Model loaded successfully from: \(modelUrl.path()) (GPU: \(useGPU))")
        } catch {
            print("[WhisperTranscribe] Failed to load model: \(error)")
        }
    }
    
    private func startPeriodicTranscription() {
        transcriptionTask = Task {
            while !Task.isCancelled && isStreaming && !isPaused {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Every 2 seconds
                
                guard let file = recordedFile, FileManager.default.fileExists(atPath: file.path) else { continue }
                
                // Check for silence using VAD
                do {
                    let samples = try decodeWaveFile(file, forLastSeconds: 2)
                    let silence = await WhisperContext.vad(samples: samples)
                    
                    if silence && displayText.isEmpty {
                        // If we detect silence and haven't transcribed anything yet, wait a bit more
                        continue
                    }
                } catch {
                    // Continue even if VAD check fails
                }
                
                // Perform incremental transcription
                await performIncrementalTranscription(file: file)
            }
        }
    }
    
    private func performIncrementalTranscription(file: URL) async {
        guard isModelLoaded, let whisperContext = whisperContext else {
            // Try loading model again with appropriate GPU setting
            await loadModel(useGPU: !isInBackground)
            return
        }
        
        do {
            // Transcribe the entire file to get all segments with proper context
            let samples = try decodeWaveFile(file)
            guard !samples.isEmpty else { return }
            
            // Transcribe the entire file
            await whisperContext.fullTranscribe(samples: samples, languageCode: currentLanguageCode)
            let segmentCount = await whisperContext.getSegmentCount()
            let allSegments = await whisperContext.getTranscriptionSegments()
            
            await MainActor.run {
                // Use the full current transcription (Whisper revises earlier segments as it gets more context)
                // Filter out blank audio segments and build the full transcript
                var fullText = ""
                for segment in allSegments {
                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Skip blank audio markers
                    if !text.isEmpty && text != "[BLANK_AUDIO]" {
                        if !fullText.isEmpty {
                            fullText += " "
                        }
                        fullText += text
                    }
                }
                
                // Only update if we have new content or if the transcription has changed
                // (Whisper might revise earlier segments, so we want to show the latest version)
                if !fullText.isEmpty {
                    // Check if this is actually new content or a revision
                    if segmentCount > lastProcessedSegmentCount {
                        // New segments added - update the display
                        accumulatedText = fullText
                        displayText = fullText
                        lastProcessedSegmentCount = segmentCount
                        lastTranscriptionTime = Date()
                    } else if fullText != accumulatedText {
                        // Same number of segments but content changed (revision) - update the display
                        accumulatedText = fullText
                        displayText = fullText
                        lastTranscriptionTime = Date()
                    }
                }
            }
        } catch {
            print("[WhisperTranscribe] Transcription error: \(error)")
        }
    }
    
    /// Extracts new text segments by comparing new transcription with previous one
    private func extractNewSegments(from newText: String, previousText: String) -> String {
        // If previous text is empty, return the new text
        guard !previousText.isEmpty else {
            return newText.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        }
        
        // Normalize both texts for comparison
        let normalizedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrev = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If new text is shorter or same, no new content
        guard normalizedNew.count > normalizedPrev.count else {
            return ""
        }
        
        // Check if new text starts with previous text (common case)
        if normalizedNew.hasPrefix(normalizedPrev) {
            // Extract the suffix as new content
            let newContent = String(normalizedNew.dropFirst(normalizedPrev.count))
            return newContent.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        }
        
        // Try to find where the new text diverges from the previous
        // This handles cases where Whisper might revise earlier segments
        let newWords = normalizedNew.components(separatedBy: .whitespaces)
        let prevWords = normalizedPrev.components(separatedBy: .whitespaces)
        
        // Find the longest common prefix
        var commonPrefixCount = 0
        let minCount = min(newWords.count, prevWords.count)
        for i in 0..<minCount {
            if newWords[i] == prevWords[i] {
                commonPrefixCount += 1
            } else {
                break
            }
        }
        
        // If there's significant overlap, extract the new words
        if commonPrefixCount >= prevWords.count / 2 {
            let newWordsOnly = newWords[commonPrefixCount...]
            return newWordsOnly.joined(separator: " ") + " "
        }
        
        // Fallback: if new text is significantly longer, assume it's mostly new content
        // This is a heuristic for when Whisper revises the transcription
        if normalizedNew.count > Int(Double(normalizedPrev.count) * 1.5) {
            // Return the difference, but be conservative
            return ""
        }
        
        return ""
    }
    
    private func performFinalTranscription(file: URL) async {
        guard isModelLoaded, let whisperContext = whisperContext else {
            await loadModel(useGPU: !isInBackground)
            guard let whisperContext = whisperContext else {
                print("[WhisperTranscribe] Model not loaded for final transcription")
                return
            }
            // Continue with transcription after loading
            return await performFinalTranscription(file: file)
        }
        
        do {
            let samples = try decodeWaveFile(file)
            guard !samples.isEmpty else { return }
            
            // Perform final transcription on the entire file
            await whisperContext.fullTranscribe(samples: samples, languageCode: currentLanguageCode)
            let finalText = await whisperContext.getTranscription()
            
            await MainActor.run {
                // Use the final transcription result (it's more accurate than accumulated)
                // But if we have accumulated text, merge them intelligently
                if !accumulatedText.isEmpty && !finalText.isEmpty {
                    // Final transcription is usually more accurate, so prefer it
                    // But we can also append any remaining text that wasn't in accumulated
                    let normalizedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedAccumulated = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // If final text contains accumulated text, use final
                    // Otherwise, append final to accumulated
                    if normalizedFinal.contains(normalizedAccumulated) || normalizedAccumulated.isEmpty {
                        displayText = normalizedFinal
                        accumulatedText = normalizedFinal
                    } else {
                        // Append any new content from final transcription
                        let newContent = extractNewSegments(from: normalizedFinal, previousText: normalizedAccumulated)
                        accumulatedText += newContent
                        displayText = accumulatedText
                    }
                } else {
                    // No accumulated text, use final transcription
                    displayText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    accumulatedText = displayText
                }
                
                // Clean up model to free memory
                self.whisperContext = nil
                self.isModelLoaded = false
            }
        } catch {
            print("[WhisperTranscribe] Final transcription error: \(error)")
        }
    }
    
    private func cleanup(deactivateAudioSession: Bool = true) {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recordedFile = nil
        isStreaming = false
        isPaused = false
        // Note: Don't clear accumulatedText here - it's used when stopping
        
        if deactivateAudioSession {
            try? session.setActive(false)
        }
    }
    
    // MARK: - AVAudioRecorderDelegate
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task { @MainActor in
                print("[WhisperTranscribe] Recording error: \(error.localizedDescription)")
                cleanup()
            }
        }
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                print("[WhisperTranscribe] Recording finished unsuccessfully")
            }
        }
    }
}

