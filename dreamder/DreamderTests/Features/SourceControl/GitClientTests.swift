//
//  GitClientTests.swift
//  DreamderTests
//
//  Created by Khan Winter on 9/11/25.
//

import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientTests {
    struct Repo {
        let fixture: GitMergeFixture
        let client: GitClient
    }

    func makeRepo(_ directory: URL) async throws -> Repo {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "one\n")
        try await fixture.commit("initial")
        return Repo(fixture: fixture, client: GitClient(directoryURL: directory, shellClient: .live()))
    }

    func relativePaths(_ files: [GitChangedFile]) -> [String] {
        files.map(\.fileURL.relativePath).sorted()
    }

    static let sampleStatus = [
        "# branch.head main",
        "1 .M N... 100644 100644 100644 aaaa bbbb dir/with space.txt",
        "2 R. N... 100644 100644 100644 aaaa bbbb R100 new name.txt",
        "old name.txt",
        "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc conflict.txt",
        "? untracked é.txt",
        "! ignored.log"
    ].joined(separator: "\0") + "\0"

    @Test
    func statusParseNullAtEnd() throws {
        try withTempDir { dirURL in
            // swiftlint:disable:next line_length
            let string = "1 .M N... 100644 100644 100644 eaef31cfa2a22418c00d7477da0b7151d122681e eaef31cfa2a22418c00d7477da0b7151d122681e Dreamder/Features/SourceControl/Client/GitClient+Status.swift\01 AM N... 000000 100644 100644 0000000000000000000000000000000000000000 e0f5ce250b32cf6610a284b7a33ac114079f5159 DreamderTests/Features/SourceControl/GitClientTests.swift\0"
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatus(Data(string.utf8))

            try #require(status.changedFiles.count == 2)
            // No null string at the end
            #expect(status.changedFiles[0].fileURL.lastPathComponent == "GitClient+Status.swift")
            #expect(status.changedFiles[1].fileURL.lastPathComponent == "GitClientTests.swift")
        }
    }

    @Test
    func statusParseHandlesEveryEntryKind() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatus(Data(Self.sampleStatus.utf8))

            #expect(status.changedFiles.map(\.fileURL.relativePath) == ["dir/with space.txt", "new name.txt"])
            #expect(status.changedFiles[0].status == .modified)
            #expect(status.changedFiles[0].stagedStatus == GitStatus.none)
            #expect(status.changedFiles[0].originalFilename == nil)
            #expect(status.changedFiles[1].stagedStatus == .renamed)
            #expect(status.changedFiles[1].originalFilename == "old name.txt")
            #expect(status.unmergedChanges.map(\.fileURL.relativePath) == ["conflict.txt"])
            #expect(status.unmergedChanges[0].status == .unmerged)
            #expect(status.untrackedFiles.map(\.fileURL.relativePath) == ["untracked é.txt"])
            #expect(status.untrackedFiles[0].status == .untracked)
        }
    }

    @Test
    func statusParseOfEmptyOutputIsEmpty() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatus(Data())
            #expect(status.changedFiles.isEmpty && status.unmergedChanges.isEmpty && status.untrackedFiles.isEmpty)
        }
    }

    @Test
    func statusParseDecodesEachPathSeparatelyWhenOneIsNotUTF8() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            var output = Data("? caf".utf8)
            output.append(contentsOf: [0xFF, 0xFE])
            output.append(contentsOf: Data("\0? ok é.txt\0".utf8))
            output.append(contentsOf: Data("2 R. N... 100644 100644 100644 aaaa bbbb R100 ".utf8))
            output.append(contentsOf: [0xC3])
            output.append(contentsOf: Data("new.txt\0old ".utf8))
            output.append(contentsOf: [0x80])
            output.append(contentsOf: Data(".txt\0".utf8))

            let status = try client.parseStatus(output)

            #expect(status.untrackedFiles.map(\.fileURL.relativePath) == ["caf\u{FFFD}\u{FFFD}", "ok é.txt"])
            #expect(status.changedFiles.map(\.fileURL.relativePath) == ["\u{FFFD}new.txt"])
            #expect(status.changedFiles.first?.originalFilename == "old \u{FFFD}.txt")
        }
    }

    @Test
    func statusParseNeverTrapsOnTruncatedOutput() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let bytes = Array(Self.sampleStatus.utf8)
            var parsed = 0
            var rejected = 0
            for length in 0...bytes.count {
                let prefix = Data(bytes[0..<length])
                do {
                    _ = try client.parseStatus(prefix)
                    parsed += 1
                } catch is GitClient.GitClientError {
                    rejected += 1
                }
            }
            #expect(parsed > 0)
            #expect(rejected > 0)
            #expect(parsed + rejected == bytes.count + 1)
        }
    }

    @Test(arguments: ["\0", "1", "1 ", "1 .M", "1 .M ", "1 .M N...", "2 R. a b c d e f g", "u", "u UU", "?", "? ", "? x", "!", "#", "x"])
    func statusParseRejectsMalformedOutputWithoutCrashing(output: String) throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            #expect(throws: GitClient.GitClientError.self) {
                try client.parseStatus(Data(output.utf8))
            }
        }
    }

    @Test
    func statusParseReportsUnknownEntryTypesAndStatusCharacters() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            #expect(throws: GitClient.GitClientError.statusInvalidChangeType("x")) {
                try client.parseStatus(Data("x file\0".utf8))
            }
            #expect(throws: GitClient.GitClientError.invalidStatus("Z")) {
                try client.parseStatus(Data("1 ZM N... 100644 100644 100644 a b path\0".utf8))
            }
        }
    }
}

extension URL {
    func createDirectoryReturningSelf() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
