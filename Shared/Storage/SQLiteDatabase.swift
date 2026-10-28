import Foundation
import SQLite3

public final class SQLiteDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let path: String

    public init(url: URL) throws {
        self.path = url.path
        try openDatabase()
        try configureDatabase()
        try createSchema()
    }

    deinit {
        closeDatabase()
    }

    private func openDatabase() throws {
        lock.lock()
        defer { lock.unlock() }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let errorMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error opening database"
            throw DatabaseError.unableToOpen(errorMsg)
        }
    }

    private func configureDatabase() throws {
        // WAL mode enables concurrent readers while writing
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        // Set busy timeout to 5000ms to safely wait if another process holds lock
        sqlite3_busy_timeout(db, 5000)
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            classification TEXT NOT NULL DEFAULT 'unspecified',
            notes TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp ASC);
        CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at ASC);
        """
        try execute(sql)
    }

    public func closeDatabase() {
        lock.lock()
        defer { lock.unlock() }
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    @discardableResult
    public func execute(_ sql: String) throws -> Void {
        lock.lock()
        defer { lock.unlock() }

        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err != nil ? String(cString: err!) : "Unknown SQL error"
            sqlite3_free(err)
            throw DatabaseError.executionFailed(message)
        }
    }

    public func performTransaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - CRUD Operations

    public func insertEvent(_ event: SleepEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        INSERT INTO events (id, event_type, timestamp, classification, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (event.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (event.type.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, (event.classification.rawValue as NSString).utf8String, -1, nil)

        if let notes = event.notes {
            sqlite3_bind_text(statement, 5, (notes as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        sqlite3_bind_double(statement, 6, event.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, event.updatedAt.timeIntervalSince1970)

        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.stepFailed(msg)
        }
    }

    public func updateEvent(_ event: SleepEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        UPDATE events SET
            event_type = ?,
            timestamp = ?,
            classification = ?,
            notes = ?,
            updated_at = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (event.type.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, (event.classification.rawValue as NSString).utf8String, -1, nil)

        if let notes = event.notes {
            sqlite3_bind_text(statement, 4, (notes as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 4)
        }

        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 6, (event.id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.stepFailed(msg)
        }
    }

    public func deleteEvent(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM events WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.stepFailed(msg)
        }
    }

    public func fetchEvent(id: UUID) throws -> SleepEvent? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, event_type, timestamp, classification, notes, created_at, updated_at FROM events WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            return parseEvent(from: statement)
        }
        return nil
    }

    public func fetchLatestEvent() throws -> SleepEvent? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, event_type, timestamp, classification, notes, created_at, updated_at FROM events ORDER BY timestamp DESC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return parseEvent(from: statement)
        }
        return nil
    }

    public func fetchAllEvents(ascending: Bool = true) throws -> [SleepEvent] {
        lock.lock()
        defer { lock.unlock() }

        let order = ascending ? "ASC" : "DESC"
        let sql = "SELECT id, event_type, timestamp, classification, notes, created_at, updated_at FROM events ORDER BY timestamp \(order);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        var events: [SleepEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let event = parseEvent(from: statement) {
                events.append(event)
            }
        }
        return events
    }

    public func fetchEvents(from startDate: Date, to endDate: Date) throws -> [SleepEvent] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, event_type, timestamp, classification, notes, created_at, updated_at
        FROM events
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)

        var events: [SleepEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let event = parseEvent(from: statement) {
                events.append(event)
            }
        }
        return events
    }

    public func deleteAllEvents() throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("DELETE FROM events;")
    }

    // MARK: - Helper

    private func parseEvent(from statement: OpaquePointer?) -> SleepEvent? {
        guard let statement = statement else { return nil }

        guard let idCString = sqlite3_column_text(statement, 0),
              let id = UUID(uuidString: String(cString: idCString)),
              let typeCString = sqlite3_column_text(statement, 1),
              let eventType = EventType(rawValue: String(cString: typeCString))
        else {
            return nil
        }

        let timestampSeconds = sqlite3_column_double(statement, 2)
        let timestamp = Date(timeIntervalSince1970: timestampSeconds)

        let classificationString = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "unspecified"
        let classification = SleepClassification(rawValue: classificationString) ?? .unspecified

        var notes: String? = nil
        if let notesCString = sqlite3_column_text(statement, 4) {
            notes = String(cString: notesCString)
        }

        let createdAtSeconds = sqlite3_column_double(statement, 5)
        let createdAt = Date(timeIntervalSince1970: createdAtSeconds)

        let updatedAtSeconds = sqlite3_column_double(statement, 6)
        let updatedAt = Date(timeIntervalSince1970: updatedAtSeconds)

        return SleepEvent(
            id: id,
            type: eventType,
            timestamp: timestamp,
            classification: classification,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
