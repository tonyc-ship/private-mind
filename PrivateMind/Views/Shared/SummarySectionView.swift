import SwiftUI
import MarkdownUI

struct SummarySectionView: View {
    let summary: String
    let isProcessing: Bool
    let onResummarize: () -> Void
    let onCopy: () -> Void
    
    @State private var isThoughtExpanded = false
    
    // Computed properties to split thought and content
    private var parsedContent: (thought: String?, content: String) {
        // Check for <think> tag using inline flag (?s) for dot-matches-newline
        if let range = summary.range(of: "(?s)<think>(.*?)(</think>|$)", options: .regularExpression) {
            let thoughtMatch = String(summary[range])
            let thoughtContent = thoughtMatch
                .replacingOccurrences(of: "<think>", with: "")
                .replacingOccurrences(of: "</think>", with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            var finalContent = summary
            finalContent.removeSubrange(range)
            finalContent = finalContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            return (thoughtContent, finalContent)
        }
        return (nil, summary)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let (thought, content) = parsedContent
                    
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
                    } else {
                        // Processing indicator if still streaming
                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating summary…")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 4)
                        }
                        
                        // Show thought block if present
                        if let thought = thought, !thought.isEmpty {
                            DisclosureGroup(
                                isExpanded: $isThoughtExpanded,
                                content: {
                                    Text(thought)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                },
                                label: {
                                    Text("Thinking Process")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }
                            )
                            .padding(.bottom, 8)
                            .onChange(of: isProcessing) { isProcessing in
                                // Auto-collapse when finished, auto-expand when starting if desired
                                // For now, let's keep user preference or default to collapsed
                                if isProcessing {
                                    isThoughtExpanded = true
                                } else {
                                    withAnimation {
                                        isThoughtExpanded = false
                                    }
                                }
                            }
                        }
                        
                        // Show final summary content
                        if !content.isEmpty {
                            Markdown(content)
                                .padding(.bottom)
                        } else if thought == nil {
                            // Fallback if no content and no thought (should happen only briefly)
                            Markdown(summary)
                                .padding(.bottom)
                        }
                    }
                }
                .padding()
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