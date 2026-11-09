import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindFileReaderTests {
    @Test
    func plainUTF8TextIsReturned() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try "héllo 😀\nworld".write(to: url, atomically: true, encoding: .utf8)
            #expect(FindFileReader.text(at: url) == "héllo 😀\nworld")
        }
    }

    @Test
    func emptyFileReadsAsEmptyText() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "empty.txt")
            try Data().write(to: url)
            #expect(FindFileReader.text(at: url) == "")
        }
    }

    @Test
    func binaryExtensionsAreSkippedRegardlessOfCase() throws {
        try withTempDir { dir in
            let lower = dir.appending(path: "a.png")
            let upper = dir.appending(path: "b.PNG")
            try "plain text".write(to: lower, atomically: true, encoding: .utf8)
            try "plain text".write(to: upper, atomically: true, encoding: .utf8)
            #expect(FindFileReader.text(at: lower) == nil)
            #expect(FindFileReader.text(at: upper) == nil)
        }
    }

    @Test
    func nulByteInsideTheSniffWindowSkipsTheFile() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "nul.txt")
            try Data([0x61, 0x62, 0x00, 0x63, 0x64]).write(to: url)
            #expect(FindFileReader.text(at: url) == nil)

            let edge = dir.appending(path: "edge.txt")
            var bytes = Data(repeating: 0x61, count: FindFileReader.sniffLength - 1)
            bytes.append(0)
            try bytes.write(to: edge)
            #expect(FindFileReader.text(at: edge) == nil)
        }
    }

    @Test
    func nulByteAfterTheSniffWindowIsNotDetected() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "late.txt")
            var bytes = Data(repeating: 0x61, count: FindFileReader.sniffLength)
            bytes.append(0)
            bytes.append(0x62)
            try bytes.write(to: url)
            let text = try #require(FindFileReader.text(at: url))
            #expect(text.utf16.count == FindFileReader.sniffLength + 2)
        }
    }

    @Test
    func filesOverTheIndexableLimitAreSkipped() throws {
        try withTempDir { dir in
            let limit = WorkspaceFileScope.maxIndexableTextSize
            let atLimit = dir.appending(path: "limit.txt")
            try Data(repeating: 0x61, count: limit).write(to: atLimit)
            #expect(FindFileReader.text(at: atLimit)?.utf8.count == limit)

            let over = dir.appending(path: "over.txt")
            try Data(repeating: 0x61, count: limit + 1).write(to: over)
            #expect(FindFileReader.text(at: over) == nil)
        }
    }

    @Test
    func invalidUTF8IsSkipped() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "latin.txt")
            try Data([0x41, 0xFF, 0xFE, 0x42]).write(to: url)
            #expect(FindFileReader.text(at: url) == nil)
        }
    }

    @Test
    func missingFileYieldsNil() throws {
        try withTempDir { dir in
            #expect(FindFileReader.text(at: dir.appending(path: "missing.txt")) == nil)
        }
    }
}
