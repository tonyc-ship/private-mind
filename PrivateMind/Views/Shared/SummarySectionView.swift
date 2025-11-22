import SwiftUI
import MarkdownUI

struct SummarySectionView: View {
    let summary: String
    let isProcessing: Bool
    let onResummarize: () -> Void
    let onCopy: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isProcessing {
                VStack(spacing: 4) {
                    ProgressView()
                    Text("Generating summary…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    Markdown(summary)
                        .padding()
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