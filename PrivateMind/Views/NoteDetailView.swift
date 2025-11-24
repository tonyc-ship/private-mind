import SwiftUI
import MarkdownUI
import UIKit

struct NoteDetailView: View {
    @StateObject private var viewModel: NoteViewModel
    @State private var selection = 0
    @State private var showCopyConfirmation = false
    @State private var isResummarizing = false
    @State private var streamingSummary = "" // For streaming summary display
    @State private var streamingTitle = "" // For streaming title display
    @State private var languageCode = "(same as the transcript)" // Default; can be replaced by user preference later

    private var transcriptLines: [String] {
        viewModel.note.transcript.components(separatedBy: .newlines)
    }

    init(note: Note) {
        _viewModel = StateObject(wrappedValue: NoteViewModel(note: note))
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Picker("", selection: $selection) {
                    Text("Summary").tag(0)
                    Text("Notes").tag(1)
                    Text("Transcript").tag(2)
                }
                .pickerStyle(.segmented)
                .padding([.top, .horizontal])

                Divider()

                GeometryReader { geometry in
                    if selection == 0 { // Summary
                        SummarySectionView(
                            summary: viewModel.note.summary,
                            isProcessing: isResummarizing,
                            onResummarize: resummarize,
                            onCopy: copyContent
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topTrailing)
                    } else if selection == 1 { // Notes
                        ZStack(alignment: .topTrailing) {
                            TextEditor(text: $viewModel.note.content)

                            CopyButtonView(action: copyContent)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                        }
                        .frame(height: geometry.size.height)
                    } else { // Transcript (read-only)
                        ZStack(alignment: .topTrailing) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(transcriptLines.indices, id: \.self) { index in
                                        Text(transcriptLines[index])
                                    }
                                }
                                .padding()
                            }

                            CopyButtonView(action: copyContent)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                        }
                        .frame(height: geometry.size.height)
                    }
                }
                .padding(.horizontal)
            }
            if showCopyConfirmation {
                Text("Copied")
                    .font(.caption)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 2)
                    .offset(y: 60)
                    .transition(.opacity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(viewModel.note.title)
                        .font(.headline)
                }
            }
        }
        .onDisappear {
            viewModel.save(note: viewModel.note)
        }
    }

    private func copyContent() {
        let contentToCopy: String
        switch selection {
        case 0:
            contentToCopy = viewModel.note.summary
        case 1:
            contentToCopy = viewModel.note.content
        case 2:
            contentToCopy = viewModel.note.transcript
        default:
            return
        }
        UIPasteboard.general.string = contentToCopy

        withAnimation {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private func bindingForSelection() -> Binding<String> {
        switch selection {
        case 0:
            return $viewModel.note.summary
        case 1:
            return $viewModel.note.content
        default:
            return $viewModel.note.transcript
        }
    }

    // MARK: - Actions
    private func resummarize() {
        Task {
            isResummarizing = true
            streamingSummary = ""
            streamingTitle = ""
            do {
                // Generate summary with streaming
                let summary = try await SummaryService.shared.generateSummary(
                    transcript: viewModel.note.transcript,
                    notes: viewModel.note.content,
                    languageCode: languageCode,
                    tokenCallback: { token in
                        streamingSummary += token
                        viewModel.note.summary = streamingSummary
                    }
                )
                viewModel.note.summary = summary

                // Optionally refresh title as well with streaming
                let title = try await SummaryService.shared.generateTitle(
                    summary: summary,
                    languageCode: languageCode,
                    tokenCallback: { token in
                        streamingTitle += token
                        if !streamingTitle.isEmpty {
                            viewModel.note.title = streamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                )
                if !title.isEmpty {
                    viewModel.note.title = title
                }
                viewModel.save(note: viewModel.note)
            } catch {
                print("Failed to resummarize note: \(error)")
            }
            isResummarizing = false
            streamingSummary = ""
            streamingTitle = ""
        }
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(note: Note(title: "This is a very long title that should be scrollable", summary: "Summary", content: "Content", transcript: "Transcript"))
    }
} 