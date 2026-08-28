import Foundation
import CSQLite

enum WarpSQLiteError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case queryFailed(String)
    case databaseMissing(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Could not open Warp database: \(message)"
        case .queryFailed(let message):
            return "Warp database query failed: \(message)"
        case .databaseMissing(let path):
            return "Warp database does not exist: \(path)"
        }
    }
}

/// Thin sqlite3 wrapper for `warp.sqlite`.
final class WarpSQLite {
    private var db: OpaquePointer?

    init(databaseURL: URL, readOnly: Bool) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: databaseURL.path, isDirectory: &isDir) || isDir.boolValue {
            throw WarpSQLiteError.databaseMissing(databaseURL.path)
        }

        var handle: OpaquePointer?
        var flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        flags |= SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed (\(rc))"
            if let handle { sqlite3_close(handle) }
            throw WarpSQLiteError.openFailed(msg)
        }
        sqlite3_busy_timeout(handle, 4000)
        db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func query(_ sql: String, binds: [String] = []) throws -> [[String: String]] {
        guard let db else { throw WarpSQLiteError.queryFailed("database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw WarpSQLiteError.queryFailed(errmsg())
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var rows: [[String: String]] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw WarpSQLiteError.queryFailed(errmsg())
            }
            var row: [String: String] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                if let cstr = sqlite3_column_text(stmt, i) {
                    row[name] = String(cString: cstr)
                } else {
                    row[name] = ""
                }
            }
            rows.append(row)
        }
        return rows
    }

    func execute(_ sql: String, binds: [String] = []) throws {
        _ = try query(sql, binds: binds)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func errmsg() -> String {
        guard let db else { return "unknown sqlite error" }
        return String(cString: sqlite3_errmsg(db))
    }
}

/// SQLite wants a C function pointer for SQLITE_TRANSIENT (-1).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
