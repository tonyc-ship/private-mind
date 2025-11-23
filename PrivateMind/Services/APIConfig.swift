import Foundation

// MARK: - APIConfig
enum APIConfig {
    // Load from Info.plist or environment variables
    // Add this key to Info.plist:
    // - SummaryEndpoint: Summary generation endpoint
    static var baseSummary: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SummaryEndpoint") as? String,
              let url = URL(string: urlString) else {
            fatalError("SummaryEndpoint must be set in Info.plist")
        }
        return url
    }
}

