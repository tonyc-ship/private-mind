import Foundation
import Combine

@MainActor
final class NoteViewModel: ObservableObject {
    @Published var note: Note
    private var cancellables = Set<AnyCancellable>()

    init(note: Note) {
        self.note = note
        
        $note
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] updatedNote in
                self?.save(note: updatedNote)
            }
            .store(in: &cancellables)
    }

    func save(note: Note) {
        Task {
            do {
                if note.id == nil {
                    // The `insert` operation returns a note with an ID.
                    // We need to update our view model's state with this new note
                    // to ensure subsequent saves are updates, not new inserts.
                    let savedNote = try await DatabaseManager.shared.insert(note: note)
                    self.note = savedNote
                } else {
                    try await DatabaseManager.shared.update(note: note)
                }
            } catch {
                print("Failed to save note: \(error)")
            }
        }
    }
} 