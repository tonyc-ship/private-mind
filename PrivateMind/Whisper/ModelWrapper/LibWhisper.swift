import Foundation
import whisper

enum WhisperError: Error {
    case couldNotInitializeContext
}

// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    nonisolated(unsafe) private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func fullTranscribe(samples: [Float], languageCode: String = "en") {
        // Leave 2 processors free (i.e. the high-efficiency cores).
        let maxThreads = max(1, min(8, cpuCount() - 2))
        
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Map language codes to Whisper language codes
        let whisperLang = WhisperContext.mapLanguageCode(languageCode)
        
        whisperLang.withCString { lang in
            // Adapted from whisper.objc
            params.print_realtime   = true
            params.print_progress   = false
            params.print_timestamps = true
            params.print_special    = false
            params.translate        = false
            params.language         = lang
            params.n_threads        = Int32(maxThreads)
            params.offset_ms        = 0
            params.no_context       = true
            params.single_segment   = false

            whisper_reset_timings(context)
            print("[Whisper] About to run whisper_full with language: \(whisperLang)")
            samples.withUnsafeBufferPointer { samples in
                if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                    print("[Whisper] Failed to run the model")
                }
            }
        }
    }

    func getTranscription() -> String {
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String.init(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }
    
    func getSegmentCount() -> Int {
        return Int(whisper_full_n_segments(context))
    }
    
    struct TranscriptionSegment {
        let text: String
    }
    
    func getTranscriptionSegments() -> [TranscriptionSegment] {
        let count = Int(whisper_full_n_segments(context))
        var segments: [TranscriptionSegment] = []
        for i in 0..<count {
            let text = String(cString: whisper_full_get_segment_text(context, Int32(i)))
            segments.append(TranscriptionSegment(text: text))
        }
        return segments
    }

    static func createContext(path: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
        print("[Whisper] Running on the simulator, using CPU")
#endif
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            return WhisperContext(context: context)
        } else {
            print("[Whisper] Couldn't load model at \(path)")
            throw WhisperError.couldNotInitializeContext
        }
    }

    static func vad(samples: [Float]) -> Bool {
        // Note: The old vad_simple_c function is no longer available in the latest whisper.cpp
        // VAD is now integrated into whisper_full_params. For simple VAD, you may need to:
        // 1. Use a separate VAD library, or
        // 2. Use whisper's built-in VAD by setting params.vad = true in whisper_full_params
        // For now, returning false (no silence detected) to maintain compatibility
        // TODO: Implement proper VAD using whisper's built-in VAD or a separate library
        return false
    }
    
    /// Maps language codes (e.g., "en-US", "zh-CN") to Whisper language codes (e.g., "en", "zh")
    private static func mapLanguageCode(_ code: String) -> String {
        // Extract base language from codes like "en-US" -> "en"
        let baseLang = code.split(separator: "-").first?.lowercased() ?? "en"
        
        // Whisper supports: en, zh, de, es, ru, ko, ja, pt, tr, pl, ca, nl, ar, sv, it, id, hi, fi, vi, he, uk, el, ms, cs, ro, da, hu, ta, no, th, ur, hr, bg, lt, la, mi, ml, cy, sk, te, fa, lv, bn, sr, az, sl, kn, et, mk, br, eu, is, hy, ne, mn, bs, kk, sq, sw, gl, mr, pa, si, km, sn, yo, so, af, oc, ka, be, tg, sd, gu, am, yi, lo, uz, fo, ht, ps, tk, nn, mt, sa, lb, my, bo, tl, mg, as, tt, haw, ln, ha, ba, jw, su
        // For simplicity, return the base language or default to "en" if not supported
        return baseLang
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}

