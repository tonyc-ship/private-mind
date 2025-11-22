import Foundation
import Combine

@MainActor
final class NotesListViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var isLoading = false
    private var cancellables = Set<AnyCancellable>()

    func load() {
        Task {
            isLoading = true

            do {
                notes = try await DatabaseManager.shared.fetchNotes().sorted { $0.createdAt > $1.createdAt }
            } catch {
                print("Failed to load notes: \(error)")
            }

            isLoading = false
        }
    }
    
    /// Refresh notes by syncing from cloud and reloading
    func refresh() async {
        await load()
    }

    /// Creates an empty note and returns it for immediate use (e.g., recording UI)
    @discardableResult
    func addEmptyNote() async -> Note? {
        let note = Note()
        do {
            let inserted = try await DatabaseManager.shared.insert(note: note)
            notes.insert(inserted, at: 0)
            return inserted
        } catch {
            print("Failed to insert note: \(error)")
            return nil
        }
    }

    /// Delete notes at offsets from the list and database
    func delete(at offsets: IndexSet) {
        let notesToDelete = offsets.map { notes[$0] }
        // Optimistically remove from UI
        notes.remove(atOffsets: offsets)

        Task {
            for note in notesToDelete {
                do {
                    try await DatabaseManager.shared.delete(note: note)
                } catch {
                    print("Failed to delete note: \(error)")
                }
            }
        }
    }

    /// Delete an array of specific notes (helper used when list is sectioned)
    func delete(notes notesToDelete: [Note]) {
        // Optimistically remove from UI
        notes.removeAll { note in
            notesToDelete.contains(note)
        }

        Task {
            for note in notesToDelete {
                do {
                    try await DatabaseManager.shared.delete(note: note)
                } catch {
                    print("Failed to delete note: \(error)")
                }
            }
        }
    }
} 