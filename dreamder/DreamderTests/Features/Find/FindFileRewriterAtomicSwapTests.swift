import Foundation
import Synchronization
import Testing
@testable import Dreamder

private struct WriterObservation: Equatable, Sendable {
    let original: Data
    let entryCount: Int
}

private final class ObservationLog<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    var values: [Value] {
        storage.withLock { $0 }
    }

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }
}

private struct WriteFailure: Error {}

@Suite
struct FindFileRewriterAtomicSwapTests {
    private func job(_ url: URL, ranges: [NSRange] = [NSRange(location: 0, length: 3)]) throws -> FindReplaceJob {
        var model = FindModel()
        model.stringToFind = "foo"
        model.stringToReplace = "quux"
        let regex = try #require(model.compileMatcher())
        return FindReplaceJob(url: url, ranges: ranges, model: model, regex: regex)
    }

    private func entries(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func observation(of url: URL) throws -> WriterObservation {
        WriterObservation(
            original: try Data(contentsOf: url),
            entryCount: try entries(in: url.deletingLastPathComponent()).count
        )
    }

    private func siblingTemporaries(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent != url.lastPathComponent }
    }

    @Test
    func theOriginalStaysCompleteAtEveryPointWhileTheReplacementIsWritten() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try Data("foo foo foo".utf8).write(to: url)
            let original = try Data(contentsOf: url)
            let log = ObservationLog<WriterObservation>()

            let outcome = FindFileRewriter.rewrite(
                try job(url, ranges: [NSRange(location: 4, length: 3)]),
                writer: { handle, data in
                    log.append(try observation(of: url))
                    try handle.write(contentsOf: data.prefix(4))
                    log.append(try observation(of: url))
                    try handle.write(contentsOf: data.dropFirst(4))
                    log.append(try observation(of: url))
                }
            )

            let expected = WriterObservation(original: original, entryCount: 2)
            #expect(outcome.isClean)
            #expect(log.values == [expected, expected, expected])
            #expect(try String(contentsOf: url, encoding: .utf8) == "foo quux foo")
            #expect(try entries(in: dir) == ["a.txt"])
        }
    }

    @Test
    func aWriterFailureLeavesTheOriginalCompleteAndRemovesTheTemporaryFile() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try Data("foo foo".utf8).write(to: url)
            let original = try Data(contentsOf: url)

            let outcome = FindFileRewriter.rewrite(
                try job(url),
                writer: { handle, _ in
                    try handle.write(contentsOf: Data("zz".utf8))
                    throw WriteFailure()
                }
            )

            guard case .failed(let message) = outcome else {
                Issue.record("expected failure, got \(outcome)")
                return
            }
            #expect(message.hasPrefix("Cannot write a.txt: "))
            #expect(try Data(contentsOf: url) == original)
            #expect(try entries(in: dir) == ["a.txt"])
        }
    }

    @Test
    func bytesChangedByAnotherProcessBeforeTheSwapAreNeverOverwritten() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try Data("foo foo".utf8).write(to: url)
            let foreign = Data("foo written elsewhere".utf8)

            let outcome = FindFileRewriter.rewrite(
                try job(url),
                writer: { handle, data in
                    try foreign.write(to: url)
                    try handle.write(contentsOf: data)
                }
            )

            #expect(outcome == .stale)
            #expect(try Data(contentsOf: url) == foreign)
            #expect(try entries(in: dir) == ["a.txt"])
        }
    }

    @Test
    func aFileDeletedBeforeTheSwapIsStale() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try Data("foo foo".utf8).write(to: url)

            let outcome = FindFileRewriter.rewrite(
                try job(url),
                writer: { handle, data in
                    try FileManager.default.removeItem(at: url)
                    try handle.write(contentsOf: data)
                }
            )

            #expect(outcome == .stale)
            #expect(try entries(in: dir).isEmpty)
        }
    }

    @Test
    func aFailedSwapIsReportedAndKeepsTheOriginal() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try Data("foo foo".utf8).write(to: url)
            let original = try Data(contentsOf: url)

            let outcome = FindFileRewriter.rewrite(
                try job(url),
                writer: { handle, data in
                    try handle.write(contentsOf: data)
                    for temporary in try siblingTemporaries(of: url) {
                        try FileManager.default.removeItem(at: temporary)
                    }
                }
            )

            guard case .failed(let message) = outcome else {
                Issue.record("expected failure, got \(outcome)")
                return
            }
            #expect(message.hasPrefix("Cannot write a.txt: "))
            #expect(try Data(contentsOf: url) == original)
            #expect(try entries(in: dir) == ["a.txt"])
        }
    }

    @Test
    func aDirectoryThatRefusesTheTemporaryFileFailsWithoutTouchingTheOriginal() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "locked", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "a.txt")
            try Data("foo foo".utf8).write(to: url)
            let original = try Data(contentsOf: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

            let outcome = FindFileRewriter.rewrite(try job(url))

            guard case .failed(let message) = outcome else {
                Issue.record("expected failure, got \(outcome)")
                return
            }
            #expect(message.hasPrefix("Cannot write a.txt: "))
            #expect(try Data(contentsOf: url) == original)
            #expect(try entries(in: folder) == ["a.txt"])
        }
    }

    @Test
    func aReadOnlyFileIsRefusedEvenInAWritableDirectory() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "locked.txt")
            try Data("foo".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

            let outcome = FindFileRewriter.rewrite(try job(url))

            #expect(outcome == .failed("Cannot write locked.txt: The file is read-only."))
            #expect(try String(contentsOf: url, encoding: .utf8) == "foo")
            #expect(try entries(in: dir) == ["locked.txt"])
        }
    }

    @Test
    func theTemporaryFileLivesBesideTheSymlinkTargetNotBesideTheLink() throws {
        try withTempDir { dir in
            let realFolder = dir.appending(path: "real", directoryHint: .isDirectory)
            let linkFolder = dir.appending(path: "links", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: true)
            let target = realFolder.appending(path: "a.txt")
            let link = linkFolder.appending(path: "a.txt")
            try Data("foo".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let targetLog = ObservationLog<WriterObservation>()
            let linkFolderLog = ObservationLog<[String]>()

            let outcome = FindFileRewriter.rewrite(
                try job(link),
                writer: { handle, data in
                    targetLog.append(try observation(of: target))
                    linkFolderLog.append(try entries(in: linkFolder))
                    try handle.write(contentsOf: data)
                }
            )

            #expect(outcome.isClean)
            #expect(targetLog.values.map(\.entryCount) == [2])
            #expect(linkFolderLog.values == [["a.txt"]])
            #expect(try String(contentsOf: target, encoding: .utf8) == "quux")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
            #expect(try entries(in: realFolder) == ["a.txt"])
        }
    }
}
