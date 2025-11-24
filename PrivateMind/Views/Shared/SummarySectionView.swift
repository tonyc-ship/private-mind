import SwiftUI
import MarkdownUI

struct SummarySectionView: View {
    let summary: String
    let isProcessing: Bool
    let onResummarize: () -> Void
    let onCopy: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isProcessing && summary.isEmpty {
                        // Show loading indicator only if summary is completely empty
                        VStack(spacing: 4) {
                            ProgressView()
                            Text("Generating summary…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if isProcessing {
                        // Show streaming summary with processing indicator
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating summary…")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 4)
                            
                            Markdown(summary)
                        }
                        .padding()
                    } else {
                        // Show final summary
                        Markdown(summary)
                            .padding()
                    }
                }
            }

            HStack(spacing: 4) {
                Button(action: onResummarize) {
                    Image(systemName: "arrow.clockwise")
                        .renderingMode(.template)
                        .foregroundColor(.primary)
                        .imageScale(.medium)
                        .padding(.vertical, 0)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                }
                .disabled(isProcessing)

                CopyButtonView(action: onCopy)
                    .disabled(isProcessing)
            }
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }
}

#Preview {
    SummarySectionView(
        summary: "# Sample Summary\nThis is a sample summary.",
        isProcessing: false,
        onResummarize: {},
        onCopy: {}
    )
} 