import Foundation
import AVFoundation
import ActivityKit

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, @unchecked Sendable {
    @Published var isRecording = false
    @Published var hasPermission = false
    @Published var isPaused = false
    @Published var elapsed: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?
    private var recordingActivity: Activity<RecordingActivityAttributes>?

    override init() {
        super.init()
        checkMicrophonePermission()
    }

    func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .undetermined:
//            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
//                Task { @MainActor [grantedValue = granted] in
//                    self?.hasPermission = grantedValue
//                }
//            }
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    func startRecording(title: String) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)

            let filename = "note-\(Date().timeIntervalSince1970).m4a"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            isPaused = false
            elapsed = 0
            startTimer()
            
            startLiveActivity(title: title)
        } catch {
            print("Could not start recording: \(error)")
            isRecording = false
        }
    }

    func stopRecording() -> URL? {
        // Capture the final, authoritative duration before tearing down the recorder.
        let finalElapsed = audioRecorder?.currentTime ?? elapsed

        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        stopTimer()
        elapsed = finalElapsed

        stopLiveActivity()

        let url = recordingURL
        recordingURL = nil
        return url
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            isRecording = false
            stopTimer()
        }
    }
    
    // MARK: - Playback Control
    
    func pause() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        stopTimer()
        updateLiveActivity()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
        startTimer()
        updateLiveActivity()
    }

    // MARK: - Timer
    
    private func startTimer() {
        timer?.invalidate()
        let refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = self.audioRecorder?.currentTime ?? self.elapsed
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Live Activity
    
    private func startLiveActivity(title: String) {
        // Default to true if not set
        let showActivity = UserDefaults.standard.object(forKey: "showRecordingLiveActivity") as? Bool ?? true
        guard showActivity else { return }
        
        let attributes = RecordingActivityAttributes(meetingTitle: title)
        let initialState = RecordingActivityAttributes.ContentState(state: .recording(startTime: .now))

        do {
            recordingActivity = try Activity<RecordingActivityAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
        } catch (let error) {
            print("Error requesting Live Activity: \(error.localizedDescription)")
        }
    }
    
    private func updateLiveActivity() {
        Task {
            let state: RecordingActivityAttributes.ContentState
            if isPaused {
                state = RecordingActivityAttributes.ContentState(state: .paused(elapsedTime: elapsed))
            } else {
                // To make the timer resume correctly, calculate a new start date
                // by subtracting the already elapsed time from the current time.
                let newStartDate = Date().addingTimeInterval(-elapsed)
                state = RecordingActivityAttributes.ContentState(state: .recording(startTime: newStartDate))
            }
            await recordingActivity?.update(using: state)
        }
    }
    
    private func stopLiveActivity() {
        Task {
            await recordingActivity?.end(dismissalPolicy: .immediate)
        }
    }
} 
