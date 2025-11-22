import Foundation
import GRDB

struct Note: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "notes"

    // Primary key managed by GRDB (AUTOINCREMENT)
    var id: Int64?

    var title: String
    var summary: String
    var content: String
    var transcript: String
    var duration: String = "0"
    var deletedAt: Date?
    var createdAt: Date

    // Provide default initializer for new notes
    init(id: Int64? = nil,
         title: String = "New Note",
         summary: String = "",
         content: String = "",
         transcript: String = "",
         duration: String = "0",
         deletedAt: Date? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.transcript = transcript
        self.duration = duration
        self.deletedAt = deletedAt
        self.createdAt = createdAt
    }

    // Define database columns for convenience
    enum Columns: String, ColumnExpression {
        case id, title, summary, content, transcript, duration, createdAt, deletedAt
    }
} 