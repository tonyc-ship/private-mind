import SwiftUI
import MarkdownUI
import UIKit

struct NewNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var viewModel: NoteViewModel
    // Support both WebSocket and Whisper transcription
    @StateObject private var websocketTranscriber = TranscribeService()
    @StateObject private var whisperTranscriber = WhisperTranscribeService()
    
    // Persist transcription method preference
    @AppStorage("useWhisperTranscription") private var useWhisperTranscription: Bool = false
    
    @State private var isRecordingFinished = false
    @State private var isGeneratingSummary = false
    @State private var selection = 0 // Recording: 0=Notes, 1=Transcript | Detail: 0=Summary, 1=Notes, 2=Transcript
    // Persist the user's last selected language across notes
    @AppStorage("selectedLanguageCode") private var languageCode: String = "en-US"
    @State private var showCopyConfirmation = false

    @State private var autoScroll = true
    private let transcriptBottomID = "transcriptBottom"

    // Controls which sheet detent is currently active (default .large)
    @State private var sheetDetent: PresentationDetent = .large
    @State private var availableDetents: Set<PresentationDetent> = [.large]

    init(note: Note) {
        _viewModel = StateObject(wrappedValue: NoteViewModel(note: note))
    }

    var body: some View {
        Group {
            if isRecordingFinished {
                detailView
            } else {
                recordingView
            }
        }
        .navigationTitle(viewModel.note.title.isEmpty ? "New Note" : viewModel.note.title)
        .navigationBarTitleDisplayMode(.inline)
        .presentationDetents(availableDetents, selection: $sheetDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(160)))
        .interactiveDismissDisabled(!isRecordingFinished)
        .onAppear {
            // Insert the compact detent on the next run loop to ensure the
            // sheet presents in .large first, eliminating the initial bounce.
            DispatchQueue.main.async {
                availableDetents.insert(.height(160))
            }
        }
        .task {
            // Auto-start recording when view appears
            if !recorder.isRecording {
                recorder.startRecording(title: viewModel.note.title.isEmpty ? "New Note" : viewModel.note.title)
                if useWhisperTranscription {
                    await whisperTranscriber.start(languageCode: languageCode, email: "")
                } else {
                    await websocketTranscriber.start(languageCode: languageCode, email: "")
                }
            }
        }
    }

    // MARK: - Subviews
    private var recordingView: some View {
        VStack(spacing: 8) {
            HStack {
                Text(timeString(from: recorder.elapsed))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Menu {
                    Picker("Language", selection: $languageCode) {
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    
                    Divider()
                    
                    Picker("Transcription", selection: $useWhisperTranscription) {
                        Label("WebSocket (Online)", systemImage: "network").tag(false)
                        Label("Whisper (On-device)", systemImage: "cpu").tag(true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(supportedLanguages.first(where: { $0.code == languageCode })?.name ?? "Language")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .onChange(of: languageCode) { newLanguageCode in
                    Task {
                        await restartTranscription(languageCode: newLanguageCode)
                    }
                }
                .onChange(of: useWhisperTranscription) { _ in
                    Task {
                        await restartTranscription(languageCode: languageCode)
                    }
                }

                // Pause/Resume Button
                Button {
                    if recorder.isPaused {
                        recorder.resume()
                        if useWhisperTranscription {
                            whisperTranscriber.resume()
                        } else {
                            websocketTranscriber.resume()
                        }
                    } else {
                        recorder.pause()
                        if useWhisperTranscription {
                            whisperTranscriber.pause()
                        } else {
                            websocketTranscriber.pause()
                        }
                    }
                } label: {
                    Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 30))
                        .labelStyle(.iconOnly)
                }

                // End Button
                Button(role: .destructive) {
                    endRecordingAndSummarize()
                } label: {
                    Label("End", systemImage: "stop.circle.fill")
                        .font(.system(size: 30))
                        .labelStyle(.iconOnly)
                }
                .foregroundColor(.red)
            }
            .padding([.horizontal, .top])

            Picker("", selection: $selection) {
                Text("Notes").tag(0)
                Text("Transcript").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selection == 0 {
                TextEditor(text: $viewModel.note.content)
                    .padding(.horizontal)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            Text(useWhisperTranscription ? whisperTranscriber.displayText : websocketTranscriber.displayText)
                                .foregroundColor((useWhisperTranscription ? whisperTranscriber.displayText : websocketTranscriber.displayText).isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)

                            Color.clear
                                .frame(height: 1)
                                .id(transcriptBottomID)
                                .onAppear { autoScroll = true }
                                .onDisappear { autoScroll = false }
                        }
                    }
                    .onChange(of: useWhisperTranscription ? whisperTranscriber.displayText : websocketTranscriber.displayText) { _ in
                        if autoScroll {
                            withAnimation {
                                proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: autoScroll) { newValue in
                        if newValue {
                            withAnimation {
                                proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom)
    }

    private var detailView: some View {
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
                            isProcessing: isGeneratingSummary,
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
                                Text(viewModel.note.transcript)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .navigationTitle(viewModel.note.title.isEmpty ? "New Note" : viewModel.note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onDisappear {
            viewModel.save(note: viewModel.note)
        }
    }

    // MARK: - Helpers
    private func endRecordingAndSummarize() {
        // Stop recording and transcription
        recorder.stopRecording()
        if useWhisperTranscription {
            whisperTranscriber.stop()
            viewModel.note.transcript = whisperTranscriber.displayText
        } else {
            websocketTranscriber.stop()
            viewModel.note.transcript = websocketTranscriber.displayText
        }
        viewModel.note.duration = String(recorder.elapsed)
        
        // Switch to detail view
        isRecordingFinished = true
        selection = 0 // Show summary tab first

        // Generate summary
        Task {
            isGeneratingSummary = true
            do {
                let transcriptText = useWhisperTranscription ? whisperTranscriber.displayText : websocketTranscriber.displayText
                let summary = try await SummaryService.shared.generateSummary(
                    transcript: transcriptText,
                    notes: viewModel.note.content,
                    languageCode: languageCode
                )
                viewModel.note.summary = summary
                
                // Generate title based on summary
                let title = try await SummaryService.shared.generateTitle(
                    summary: summary,
                    languageCode: languageCode
                )
                if !title.isEmpty {
                    viewModel.note.title = title
                }
            } catch {
                print("Failed to summarize: \(error)")
                viewModel.note.summary = "Error: Could not generate summary."
            }
            isGeneratingSummary = false
            viewModel.save(note: viewModel.note) // Save after summary generation
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

    private func resummarize() {
        Task {
            isGeneratingSummary = true
            do {
                let summary = try await SummaryService.shared.generateSummary(
                    transcript: viewModel.note.transcript,
                    notes: viewModel.note.content,
                    languageCode: languageCode
                )
                viewModel.note.summary = summary

                // Optionally refresh title as well
                let title = try await SummaryService.shared.generateTitle(
                    summary: summary,
                    languageCode: languageCode
                )
                if !title.isEmpty {
                    viewModel.note.title = title
                }
                viewModel.save(note: viewModel.note)
            } catch {
                print("Failed to resummarize note: \(error)")
            }
            isGeneratingSummary = false
        }
    }

    private func restartTranscription(languageCode: String) async {
        if useWhisperTranscription {
            whisperTranscriber.stop(deactivateAudioSession: false)
            await whisperTranscriber.start(languageCode: languageCode, email: "")
        } else {
            websocketTranscriber.stop(deactivateAudioSession: false)
            await websocketTranscriber.start(languageCode: languageCode, email: "")
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    NewNoteView(note: Note())
} 