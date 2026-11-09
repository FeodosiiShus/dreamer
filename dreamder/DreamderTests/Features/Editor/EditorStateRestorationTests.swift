//
//  EditorStateRestorationTests.swift
//  DreamderTests
//
//  Created by Khan Winter on 7/3/25.
//

import Testing
import Foundation
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorStateRestorationTests {
    @Test
    func createsDatabase() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            _ = try EditorStateRestoration(url)
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test
    func savesAndRetrievesStateForFile() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            let restoration = try EditorStateRestoration(url)

            // Update some state
            restoration.updateRestorationState(
                for: dir.appending(path: "file.txt"),
                data: .init(cursorPositions: [], scrollPosition: .zero)
            )

            // Retrieve it
            #expect(
                restoration.restorationState(for: dir.appending(path: "file.txt"))
                == EditorStateRestoration.StateRestorationData(cursorPositions: [], scrollPosition: .zero)
            )
        }
    }

    @Test
    func savesScrollPosition() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            let restoration = try EditorStateRestoration(url)

            // Update some state
            restoration.updateRestorationState(
                for: dir.appending(path: "file.txt"),
                data: .init(cursorPositions: [], scrollPosition: CGPoint(x: 100, y: 100))
            )

            // Retrieve it
            #expect(
                restoration.restorationState(for: dir.appending(path: "file.txt"))
                == EditorStateRestoration.StateRestorationData(
                    cursorPositions: [],
                    scrollPosition: CGPoint(x: 100, y: 100)
                )
            )
        }
    }

    @Test
    func clearsCorruptedDatabase() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "database.db")
            try "bad data".write(to: url, atomically: true, encoding: .utf8)
            // This will throw if it can't connect to the database.
            _ = try EditorStateRestoration(url)
        }
    }

    @Test
    func anUnusableDatabaseLocationThrows() throws {
        try withTempDir { dir in
            let blocker = dir.appending(path: "blocker")
            try "file".write(to: blocker, atomically: true, encoding: .utf8)
            let url = blocker.appending(path: "database.db")

            #expect(throws: (any Error).self) {
                _ = try EditorStateRestoration(url)
            }
        }
    }
}
