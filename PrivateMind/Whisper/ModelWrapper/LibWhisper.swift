import Foundation
// Note: Whisper functionality was part of the old llamaforked package.
// You may need to integrate whisper.cpp separately or find an alternative solution.
// For now, commenting out to allow the project to compile.
// import WhisperFramework

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
        // whisper_free(context)  // Whisper not available - need to integrate whisper.cpp separately
    }

    func fullTranscribe(samples: [Float], languageCode: String = "en") {
        // TODO: Whisper functionality is not available - whisper.cpp needs to be integrated separately
        // The old llamaforked package included both llama.cpp and whisper.cpp, but they are separate projects
        print("[Whisper] ERROR: Whisper functionality not available. Please integrate whisper.cpp separately.")
        // Original code commented out:
        /*
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let whisperLang = WhisperContext.mapLanguageCode(languageCode)
        whisperLang.withCString { lang in
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
            samples.withUnsafeBufferPointer { samples in
                if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                    print("[Whisper] Failed to run the model")
                }
            }
        }
        */
    }

    func getTranscription() -> String {
        // TODO: Whisper not available
        return ""
        // Original: for i in 0..<whisper_full_n_segments(context) { ... }
    }
    
    func getSegmentCount() -> Int {
        // TODO: Whisper not available
        return 0
        // Original: return Int(whisper_full_n_segments(context))
    }
    
    struct TranscriptionSegment {
        let text: String
    }
    
    func getTranscriptionSegments() -> [TranscriptionSegment] {
        // TODO: Whisper not available
        return []
        // Original: let count = Int(whisper_full_n_segments(context)) ...
    }

    static func createContext(path: String) throws -> WhisperContext {
        // TODO: Whisper not available - need to integrate whisper.cpp separately
        print("[Whisper] ERROR: Whisper functionality not available. Please integrate whisper.cpp separately.")
        throw WhisperError.couldNotInitializeContext
        // Original code commented out:
        /*
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #endif
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            return WhisperContext(context: context)
        } else {
            throw WhisperError.couldNotInitializeContext
        }
        */
    }

    static func vad(samples: [Float]) -> Bool {
        // TODO: Whisper not available
        return false
        // Original: let silence = vad_simple_c(&samples, Int32(samples.count), Int32(sampleRate), Int32(lastMs), vadThold, freqThold, verbose ? 1 : 0)
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

