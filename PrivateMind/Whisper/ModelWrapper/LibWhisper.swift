import Foundation
import llamaforked

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
        print("[Whisper] Selecting \(maxThreads) threads")
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
                } else {
                    whisper_print_timings(context)
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
        // call public func vad_simple_c(_ data: UnsafeMutablePointer<Float>!, _ length: Int32, _ sample_rate: Int32, _ last_ms: Int32, _ vad_thold: Float, _ freq_thold: Float, _ verbose: Int32) -> Int32

        var samples = samples
        let sampleRate = 16000
        let lastMs = 1250
        let vadThold: Float = 0.6
        let freqThold: Float = 100
        let verbose = false
        let silence = vad_simple_c(&samples, Int32(samples.count), Int32(sampleRate), Int32(lastMs), vadThold, freqThold, verbose ? 1 : 0)
        return silence == 1
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

