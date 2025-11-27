import SwiftUI

struct NotesListView: View {
    @StateObject private var viewModel = NotesListViewModel()
    @ObservedObject private var navManager = NavigationManager.shared
    @State private var showNewNoteSheet = false
    @State private var pendingNote: Note?
    @State private var showSettings = false

    /// Notes grouped by calendar day, newest day first
    private var groupedNotes: [(date: Date, notes: [Note])]
    {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.notes) { note in
            calendar.startOfDay(for: note.createdAt)
        }

        return grouped
            .map { (date: $0.key, notes: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                List {
                    if viewModel.isLoading && viewModel.notes.isEmpty {
                        LoadingView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if viewModel.notes.isEmpty {
                        EmptyStateView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(groupedNotes, id: \.date) { section in
                            Section {
                                ForEach(section.notes) { note in
                                    NavigationLink(value: note) {
                                        NoteCardView(note: note)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            viewModel.delete(notes: [note])
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(section.date, format: Date.FormatStyle.dateTime.year().month().day())
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.clear)
                            }
                            .listSectionSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // keep our gradient visible
                .refreshable {
                    await viewModel.refresh()
                }
            }
            .navigationTitle("My Notes")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(.label))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            if let note = await viewModel.addEmptyNote() {
                                pendingNote = note
                                showNewNoteSheet = true
                            }
                        }
                    } label: {
                        Text("New Note")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(.label))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNewNoteSheet, onDismiss: {
                viewModel.load()
            }) {
                if let note = pendingNote {
                    NavigationStack {
                        NewNoteView(note: note)
                    }
                }
            }
            .onAppear {
                viewModel.load()
                
                if navManager.shouldStartNewNote {
                    navManager.shouldStartNewNote = false
                    startNewNote()
                }
            }
            .onChange(of: navManager.shouldStartNewNote) { shouldStart in
                if shouldStart {
                    navManager.shouldStartNewNote = false
                    startNewNote()
                }
            }
        }
    }
    
    private func startNewNote() {
        Task {
            if let note = await viewModel.addEmptyNote() {
                pendingNote = note
                showNewNoteSheet = true
            }
        }
    }
}

// MARK: - Supporting Views

struct NoteCardView: View {
    let note: Note
    
    private var formattedDuration: String {
        // Parse duration from string and format it nicely
        if let seconds = Double(note.duration), seconds > 0 {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            if minutes > 0 {
                return "\(minutes)m \(remainingSeconds)s"
            } else {
                return "\(remainingSeconds)s"
            }
        }
        return "0s"
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Visual indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 24)
            
            // Note content
            VStack(alignment: .leading, spacing: 8) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 12) {
                    // Creation time
                    Text(note.createdAt, format: Date.FormatStyle.dateTime.hour().minute())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    // Duration
                    if note.duration != "0" {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            
                            Text(formattedDuration)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .contentShape(Rectangle())
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.blue)
            
            Text("Loading your notes...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            VStack(spacing: 8) {
                Text("No Notes Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("Tap the + button to create your first note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

#Preview {
    NotesListView()
} 
