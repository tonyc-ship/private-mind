import Foundation
import AVFoundation
import Combine

/// Service that captures microphone audio, streams it via WebSocket to the same /ws/transcribe
/// endpoint used by the Electron version, and publishes partial/final transcript messages.
@MainActor
final class TranscribeService: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    // MARK: - Published values
    @Published var isStreaming = false
    @Published var isPaused = false
    @Published var lastTranscript: TranscriptMessage?
    @Published var displayText: String = ""

    // MARK: - Private properties
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var websocket: URLSessionWebSocketTask?
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    private var accumulatedText: String = ""
    private var partialText: String = ""

    // Reconnection state
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 100
    private var reconnectDelay: TimeInterval = 1.0
    private var reconnectTask: Task<Void, Never>?
    // Prevents spamming "Connection failure" logs while a reconnect is already scheduled
    private var hasPendingReconnect = false

    // Keep track of the parameters needed to reconnect
    private var currentLanguageCode: String = "en-US"
    private var currentEmail: String = ""

    // Hold on to the URLSession so the delegate callbacks keep working
    private var urlSession: URLSession?

    // MARK: - Public API
    /// Starts streaming the microphone audio. When finished, call `stop()`.
    func start(languageCode: String = "en-US", email: String) async {
        guard !isStreaming else { return }

        do {
            // Remember params for potential reconnects
            currentLanguageCode = languageCode
            currentEmail = email

            // Reset reconnection state for a fresh start
            reconnectAttempts = 0
            reconnectDelay = 1.0

            try configureAudioSession()
            setupEngine()
            try await connectWebSocket(languageCode: languageCode, email: email)
            try engine?.start()
            isStreaming = true
            isPaused = false
        } catch {
            print("[Transcribe] Failed to start: \(error)")
            cleanup(deactivateAudioSession: true)
        }
    }

    // Replace the old `stop()` with a new version that allows keeping the audio session active.
    func stop(deactivateAudioSession: Bool = true) {
        guard isStreaming else { return }
        cleanup(deactivateAudioSession: deactivateAudioSession)
        isStreaming = false
        isPaused = false
    }

    func pause() {
        guard isStreaming, !isPaused else { return }
        engine?.pause()
        isPaused = true
    }

    func resume() {
        guard isStreaming, isPaused else { return }
        do {
            try engine?.start()
            isPaused = false
        } catch {
            print("[Transcribe] Failed to resume engine: \(error)")
        }
    }

    // MARK: - Setup helpers
    private func configureAudioSession() throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func setupEngine() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16_000,
                                         channels: 1,
                                         interleaved: true)!
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.handle(buffer: buffer, converter: converter, targetFormat: outputFormat)
            }
        }

        self.engine = engine
        self.converter = converter
    }

    // MARK: - Audio processing
    private func handle(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        guard let ws = websocket, ws.state == .running else { return }

        let pcmBufferCapacity = AVAudioFrameCount(targetFormat.sampleRate / 10) // 100ms chunk
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: pcmBufferCapacity) else { return }

        var error: NSError?
        let status = converter.convert(to: pcmBuffer, error: &error) { _, outStatus -> AVAudioBuffer? in
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil {
            print("[Transcribe] Conversion error: \(String(describing: error))")
            return
        }

        guard pcmBuffer.frameLength > 0 else { return }

        if let channelData = pcmBuffer.int16ChannelData {
            let frameCount = Int(pcmBuffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameCount * 2) // 2 bytes per int16 sample
            ws.send(.data(data)) { [weak self] error in
                if let error = error {
                    print("[Transcribe] WebSocket send error: \(error)")
                    Task { @MainActor [weak self] in
                        self?.handleConnectionFailure(error)
                    }
                }
            }
        }
    }

    // MARK: - WebSocket
    private func connectWebSocket(languageCode: String, email: String) async throws {
        guard websocket == nil else { return }
        let url = makeWebSocketURL(languageCode: languageCode, email: email)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.websocket = task
        task.resume()
        listenMessages()
    }

    private func listenMessages() {
        websocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("[Transcribe] WebSocket receive error: \(error)")
                Task { @MainActor [weak self] in
                    self?.handleConnectionFailure(error)
                }
            case .success(let message):
                switch message {
                case .data(let data):
                    Task { @MainActor [weak self] in
                        self?.handleMessageData(data)
                    }
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        Task { @MainActor [weak self] in
                            self?.handleMessageData(data)
                        }
                    }
                @unknown default:
                    break
                }
                // Continue listening on main actor
                Task { @MainActor [weak self] in
                    self?.listenMessages()
                }
            }
        }
    }

    private func handleMessageData(_ data: Data) {
        do {
            // Any successful message means the connection is healthy – reset the reconnect counters
            reconnectAttempts = 0
            reconnectDelay = 1.0

            let transcript = try JSONDecoder().decode(TranscriptMessage.self, from: data)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastTranscript = transcript

                if let isFinal = transcript.isFinal, isFinal {
                    self.accumulatedText += transcript.text + " "
                    self.partialText = ""
                } else {
                    self.partialText = transcript.text
                }
                self.displayText = self.accumulatedText + self.partialText
            }
        } catch {
            print("[Transcribe] Failed to decode transcript: \(error)")
        }
    }

    private func makeWebSocketURL(languageCode: String, email: String) -> URL {
        // Choose provider based on language (mirrors Electron logic)
        let isChinese = languageCode == "zh-CN"
        let base = isChinese ? APIConfig.baseTC : APIConfig.baseAWS
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/ws/transcribe"
        comps.queryItems = [
            URLQueryItem(name: "src", value: "mic"),
            URLQueryItem(name: "sr", value: "16000"),
            URLQueryItem(name: "lang", value: languageCode),
            URLQueryItem(name: "em", value: email)
        ]
        return comps.url!
    }

    // MARK: - Reconnection helpers
    private func handleConnectionFailure(_ error: Error?) {
        guard isStreaming, !hasPendingReconnect else { return }

        hasPendingReconnect = true
        print("[Transcribe] Connection failure: \(String(describing: error))")

        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, reconnectAttempts < maxReconnectAttempts, isStreaming else { return }

        let attempt = reconnectAttempts + 1
        let delay = reconnectDelay

        reconnectTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            print("[Transcribe] Reconnecting in \(delay) seconds (attempt \(attempt)/\(self.maxReconnectAttempts))")

            try? await Task.sleep(nanoseconds: UInt64(delay * Double(NSEC_PER_SEC)))

            // Prepare next back-off
            self.reconnectAttempts += 1
            self.reconnectDelay = min(self.reconnectDelay * 2, 30)

            do {
                try await self.connectWebSocket(languageCode: self.currentLanguageCode, email: self.currentEmail)
                // Connection attempt initiated; consider failure cycle resolved for logging purposes
                self.hasPendingReconnect = false
                self.reconnectTask = nil
            } catch {
                // Something went wrong – clear task and try again (if under limit)
                self.reconnectTask = nil
                self.scheduleReconnect()
            }
        }
    }

    // MARK: - Cleanup
    private func cleanup(deactivateAudioSession: Bool = true) {
        reconnectTask?.cancel()
        reconnectTask = nil

        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        converter = nil
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        if deactivateAudioSession {
            try? session.setActive(false)
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in
            self?.handleConnectionFailure(nil)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            self?.handleConnectionFailure(error)
        }
    }
}

// MARK: - Models
struct TranscriptMessage: Hashable {
    let text: String
    let isFinal: Bool?
}

extension TranscriptMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case text // for legacy schema
        case isFinal // legacy
        case IsPartial // AWS / Tencent
        case Alternatives // AWS / Tencent
    }

    private struct Alternative: Decodable {
        let Transcript: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try AWS/Tencent schema first (Alternatives array)
        if let alternatives = try container.decodeIfPresent([Alternative].self, forKey: .Alternatives) {
            text = alternatives.first?.Transcript ?? ""
            let isPartial = try container.decodeIfPresent(Bool.self, forKey: .IsPartial) ?? true
            isFinal = !isPartial
            return
        }

        // Fallback to legacy schema { text, isFinal }
        if let txt = try container.decodeIfPresent(String.self, forKey: .text) {
            text = txt
            isFinal = try container.decodeIfPresent(Bool.self, forKey: .isFinal)
            return
        }

        // If we reach here, decoding failed
        text = ""
        isFinal = nil
    }
}

// MARK: - APIConfig
enum APIConfig {
    // Load from Info.plist or environment variables
    // Add these keys to Info.plist:
    // - TranscriptionAWSEndpoint: AWS transcription endpoint
    // - TranscriptionTencentEndpoint: Tencent transcription endpoint
    // - SummaryEndpoint: Summary generation endpoint
    static var baseAWS: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "TranscriptionAWSEndpoint") as? String,
              let url = URL(string: urlString) else {
            fatalError("TranscriptionAWSEndpoint must be set in Info.plist")
        }
        return url
    }
    
    static var baseTC: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "TranscriptionTencentEndpoint") as? String,
              let url = URL(string: urlString) else {
            fatalError("TranscriptionTencentEndpoint must be set in Info.plist")
        }
        return url
    }
    
    static var baseSummary: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SummaryEndpoint") as? String,
              let url = URL(string: urlString) else {
            fatalError("SummaryEndpoint must be set in Info.plist")
        }
        return url
    }
}
