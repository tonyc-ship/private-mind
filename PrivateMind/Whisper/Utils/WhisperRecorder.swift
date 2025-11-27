import Foundation
import AVFoundation

actor WhisperRecorder {
    private var recorder: AVAudioRecorder?
    
    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    func startRecording(toOutputFile url: URL, delegate: AVAudioRecorderDelegate?) throws {
        let recordSettings: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
#if !os(macOS)
        // Note: Audio session is configured by WhisperTranscribeService
        // Don't reconfigure here to avoid conflicts
        // let session = AVAudioSession.sharedInstance()
        // try session.setCategory(.playAndRecord, mode: .default)
#endif
        let recorder = try AVAudioRecorder(url: url, settings: recordSettings)
        recorder.delegate = delegate
        if recorder.record() == false {
            print("[WhisperRecorder] Could not start recording")
            throw RecorderError.couldNotStartRecording
        }
        self.recorder = recorder
    }
    
    func stopRecording() {
        recorder?.stop()
        recorder = nil
    }
}

