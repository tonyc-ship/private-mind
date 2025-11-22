import Foundation
import AVFoundation
import Combine

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
    
    private var currentLanguageCode: String = "en-US"
    private var modelUrl: URL? {
        Bundle.main.url(forResource: "ggml-base.en-q5_0", withExtension: "bin", subdirectory: "whisper")
    }
    
    private var transcriptionTask: Task<Void, Never>?
    private var isModelLoaded = false
    
    // MARK: - Public API
    /// Starts recording and transcribing with Whisper.
    func start(languageCode: String = "en-US", email: String = "") async {
        guard !isStreaming else { return }
        
        currentLanguageCode = languageCode
        displayText = ""
        
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
            Task {
                await loadModel()
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
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func loadModel() async {
        guard !isModelLoaded, whisperContext == nil else { return }
        
        guard let modelUrl else {
            print("[WhisperTranscribe] Whisper model not found in bundle")
            return
        }
        
        do {
            whisperContext = try WhisperContext.createContext(path: modelUrl.path())
            isModelLoaded = true
            print("[WhisperTranscribe] Model loaded successfully")
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
            // Try loading model again
            await loadModel()
            return
        }
        
        do {
            let samples = try decodeWaveFile(file, forLastSeconds: 5) // Last 5 seconds
            guard !samples.isEmpty else { return }
            
            // Create a temporary context for incremental transcription
            // Note: This is a simplified approach. For better real-time transcription,
            // you might want to use streaming transcription if available in the Whisper API
            await whisperContext.fullTranscribe(samples: samples, languageCode: currentLanguageCode)
            let text = await whisperContext.getTranscription()
            
            await MainActor.run {
                if !text.isEmpty {
                    displayText = text
                }
            }
        } catch {
            print("[WhisperTranscribe] Transcription error: \(error)")
        }
    }
    
    private func performFinalTranscription(file: URL) async {
        guard isModelLoaded, let whisperContext = whisperContext else {
            await loadModel()
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
            
            await whisperContext.fullTranscribe(samples: samples, languageCode: currentLanguageCode)
            let text = await whisperContext.getTranscription()
            
            await MainActor.run {
                displayText = text
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

