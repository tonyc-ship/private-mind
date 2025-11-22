import Foundation

/// A very small file-based logger that captures everything printed with `print` and
/// appends it to a log file inside the app’s Documents directory. The same `print`
/// API that you already use continues to work – no call-sites need to change.
///
/// The log file can be accessed via the Files app ("On My iPhone › <App Name>") or
/// through Finder when the device is connected, making it easy to grab logs from
/// a physical device for debugging.
private enum _FileLogger {
    /// Location of the log file: <Documents>/privatemind.log
    static let logURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("privatemind.log")
    }()

    /// Single ISO 8601 formatter reused for every log entry.
    /// Access only from the serial queue to ensure thread safety.
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fmt.timeZone = .current
        return fmt
    }()

    /// Thread-safe serial queue so writes don't collide.
    private static let queue = DispatchQueue(label: "com.privatemind.fileLogger")

    /// Writes the supplied string (already timestamped) to the log file.
    static func append(_ string: String) {
        queue.async {
            guard let data = string.data(using: .utf8) else { return }

            // Create the file if it doesn’t exist yet.
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            do {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // If writing fails we still don’t want to crash the app, so just fall back to console output.
                Swift.print("[FileLogger] failed to write log: \(error)")
            }
        }
    }

    /// Converts the variadic `print` items into a single string, adds a timestamp,
    /// and writes it out.
    static func log(items: [Any], separator: String, terminator: String) {
        let messageBody = items.map { String(describing: $0) }.joined(separator: separator)
        // Access dateFormatter from the serial queue to ensure thread safety
        let timestamp = queue.sync {
            dateFormatter.string(from: Date())
        }
        let fullMessage = "[\(timestamp)] \(messageBody)\(terminator)"

        // Still show in Xcode's console when debugging.
        #if DEBUG
        Swift.print(fullMessage, separator: "", terminator: "")
        #endif

        append(fullMessage)
    }
}

/// Override the global `print` function so every existing `print` call in the
/// project automatically goes through our logger without changing any call-sites.
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    _FileLogger.log(items: items, separator: separator, terminator: terminator)
} 