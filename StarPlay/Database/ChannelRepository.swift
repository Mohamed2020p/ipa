import Foundation
import SQLite3

final class ChannelRepository {
    private var db: OpaquePointer?

    init() {
        let dir  = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = dir.appendingPathComponent("starplay.db").path
        if sqlite3_open(path, &db) == SQLITE_OK {
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            createSchema()
        }
    }

    private func createSchema() {
        sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS channels (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            name     TEXT NOT NULL,
            url      TEXT NOT NULL UNIQUE,
            category TEXT NOT NULL,
            logo     TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_cat  ON channels(category);
        CREATE INDEX IF NOT EXISTS idx_name ON channels(name COLLATE NOCASE);
        """, nil, nil, nil)
    }

    func clearAll() { sqlite3_exec(db, "DELETE FROM channels;", nil, nil, nil) }

    func insertBatch(_ channels: [Channel]) {
        guard !channels.isEmpty else { return }
        sqlite3_exec(db, "BEGIN;", nil, nil, nil)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO channels(name,url,category,logo) VALUES(?,?,?,?);", -1, &stmt, nil)
        for ch in channels {
            sqlite3_bind_text(stmt, 1, (ch.name     as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (ch.url      as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (ch.category as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (ch.logo     as NSString).utf8String, -1, nil)
            sqlite3_step(stmt); sqlite3_reset(stmt)
        }
        sqlite3_finalize(stmt)
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func getCategories() -> [String] {
        var list: [String] = []
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT DISTINCT category FROM channels ORDER BY category;", -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { list.append(String(cString: c)) }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getTotalCount(category: String, search: String) -> Int {
        let (w, a) = where_(category: category, search: search)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM channels \(w);", -1, &stmt, nil)
        bind(stmt, args: a)
        var n = 0
        if sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int(stmt, 0)) }
        sqlite3_finalize(stmt)
        return n
    }

    func getPage(category: String, search: String, offset: Int, limit: Int) -> [Channel] {
        var list: [Channel] = []
        let (w, a) = where_(category: category, search: search)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT name,url,category,logo FROM channels \(w) ORDER BY name LIMIT \(limit) OFFSET \(offset);", -1, &stmt, nil)
        bind(stmt, args: a)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let n  = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let u  = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let ca = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let lo = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            list.append(Channel(name: n, url: u, category: ca, logo: lo))
        }
        sqlite3_finalize(stmt)
        return list
    }

    private func where_(category: String, search: String) -> (String, [String]) {
        var c: [String] = []; var a: [String] = []
        if category != "__all__" { c.append("category = ?"); a.append(category) }
        if !search.isEmpty       { c.append("name LIKE ? COLLATE NOCASE"); a.append("%\(search)%") }
        return (c.isEmpty ? "" : "WHERE " + c.joined(separator: " AND "), a)
    }

    private func bind(_ stmt: OpaquePointer?, args: [String]) {
        for (i, v) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (v as NSString).utf8String, -1, nil)
        }
    }

    deinit { sqlite3_close(db) }
}
