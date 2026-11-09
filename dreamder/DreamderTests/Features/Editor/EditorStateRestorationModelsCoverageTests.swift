import Foundation
import SQLite3
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorStateRestorationModelsCoverageTests {
    private struct SQLiteFailure: Error {
        let code: Int32
    }

    private func execute(_ statement: String, at url: URL) throws {
        var handle: OpaquePointer?
        let opened = sqlite3_open(url.path(percentEncoded: false), &handle)
        defer { sqlite3_close(handle) }
        guard opened == SQLITE_OK else { throw SQLiteFailure(code: opened) }
        let executed = sqlite3_exec(handle, statement, nil, nil, nil)
        guard executed == SQLITE_OK else { throw SQLiteFailure(code: executed) }
    }

    @Test
    func unopenableDatabaseThrowsAfterTheRetry() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "missing/sub/database.db")

            #expect(throws: (any Error).self) {
                _ = try EditorStateRestoration(url)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test
    func writeFailureIsSwallowedAndNothingIsStored() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            let file = dir.appending(path: "file.txt")
            let restoration = try EditorStateRestoration(url)
            try execute("DROP TABLE stateRestorationRecord", at: url)

            restoration.updateRestorationState(
                for: file,
                data: .init(cursorPositions: [], scrollPosition: CGPoint(x: 1, y: 2))
            )

            #expect(restoration.restorationState(for: file) == nil)
        }
    }

    @Test
    func undecodableRowYieldsNoState() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            let file = dir.appending(path: "file.txt")
            let restoration = try EditorStateRestoration(url)
            restoration.updateRestorationState(
                for: file,
                data: .init(cursorPositions: [], scrollPosition: CGPoint(x: 1, y: 2))
            )
            #expect(restoration.restorationState(for: file) != nil)

            try execute("UPDATE stateRestorationRecord SET data = X'6E6F74206A736F6E'", at: url)

            #expect(restoration.restorationState(for: file) == nil)
        }
    }

    @Test
    func unknownFileHasNoState() throws {
        try withTempDir { dir in
            let restoration = try EditorStateRestoration(dir.appending(path: "database.db"))

            #expect(restoration.restorationState(for: dir.appending(path: "never-saved.txt")) == nil)
        }
    }
}
