import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private(set) var dbQueue: DatabaseQueue!

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            // Locate database file in Application Support directory
            let fm = FileManager.default
            let appSupportURL = try fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true)
            let dbURL = appSupportURL.appendingPathComponent("privatemind.sqlite")

            // Create parent directory if necessary
            try fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            dbQueue = try DatabaseQueue(path: dbURL.path)

            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    // MARK: - Migrations
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createNotes") { db in
            try db.create(table: Note.databaseTableName) { t in
                t.column(Note.Columns.id.name, .integer).primaryKey(autoincrement: true)
                t.column(Note.Columns.title.name, .text).notNull()
                t.column(Note.Columns.summary.name, .text).notNull()
                t.column(Note.Columns.content.name, .text).notNull()
                t.column(Note.Columns.transcript.name, .text).notNull()
                t.column(Note.Columns.createdAt.name, .date).notNull()
            }
        }

        migrator.registerMigration("addDuration") { db in
            try db.alter(table: Note.databaseTableName) { t in
                t.add(column: Note.Columns.duration.name, .text).defaults(to: "0")
            }
        }

        migrator.registerMigration("addDeletedAt") { db in
            try db.alter(table: Note.databaseTableName) { t in
                t.add(column: Note.Columns.deletedAt.name, .date)
            }
        }

        return migrator
    }

    // MARK: - CRUD helpers
    func fetchNotes() async throws -> [Note] {
        try await dbQueue.read { db in
            try Note
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Inserts a note and returns the persisted copy (with primary key set).
    func insert(note: Note) async throws -> Note {
        let insertedID: Int64 = try await dbQueue.write { db in
            var noteToInsert = note
            try noteToInsert.insert(db)
            return noteToInsert.id ?? db.lastInsertedRowID
        }
        var insertedNote = note
        insertedNote.id = insertedID
        return insertedNote
    }

    func update(note: Note) async throws {
        _ = try await dbQueue.write { db in
            try note.update(db)
        }
    }

    func delete(note: Note) async throws {
        var toDelete = note
        toDelete.deletedAt = Date()
        try await update(note: toDelete)
    }
} 