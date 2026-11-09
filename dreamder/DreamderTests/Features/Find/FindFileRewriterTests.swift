import Darwin
import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindFileRewriterTests {
    private func job(
        _ url: URL,
        find: String = "foo",
        replace: String = "quux",
        ranges: [NSRange]
    ) throws -> FindReplaceJob {
        var model = FindModel()
        model.stringToFind = find
        model.stringToReplace = replace
        let regex = try #require(model.compileMatcher())
        return FindReplaceJob(url: url, ranges: ranges, model: model, regex: regex)
    }

    private func write(_ text: String, to url: URL, permissions: Int = 0o644) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func attributes(of url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    private func permissions(of url: URL) throws -> Int {
        try (attributes(of: url)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func owner(of url: URL) throws -> Int {
        try (attributes(of: url)[.ownerAccountID] as? NSNumber)?.intValue ?? -1
    }

    private func text(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test
    func replacesTheSelectedRange() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try write("foo foo foo", to: url)
            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 4, length: 3)]))
            #expect(
                outcome == .replaced(
                    FindReplaceResult(
                        text: "foo quux foo",
                        applied: [FindReplaceEdit(range: NSRange(location: 4, length: 3), replacement: "quux")],
                        missing: 0
                    )
                )
            )
            #expect(outcome.isClean)
            #expect(try text(of: url) == "foo quux foo")
        }
    }

    @Test
    func shrinkingReplacementTruncatesTheFile() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try write("foofoofoo", to: url)
            let outcome = FindFileRewriter.rewrite(
                try job(url, replace: "", ranges: [NSRange(location: 0, length: 3), NSRange(location: 3, length: 3)])
            )
            #expect(outcome.isClean)
            #expect(try text(of: url) == "foo")
        }
    }

    @Test
    func keepsPermissionsAndOwner() throws {
        try withTempDir { dir in
            for mode in [0o751, 0o600] {
                let url = dir.appending(path: "mode-\(mode).txt")
                try write("foo", to: url, permissions: mode)
                let ownerBefore = try owner(of: url)

                let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 0, length: 3)]))

                #expect(outcome.isClean)
                #expect(try text(of: url) == "quux")
                #expect(try permissions(of: url) == mode)
                #expect(try owner(of: url) == ownerBefore)
            }
        }
    }

    @Test
    func keepsExtendedAttributes() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "xattr.txt")
            try write("foo", to: url)
            let name = "com.dreamder.find.test"
            let payload: [UInt8] = [1, 2, 3]
            let status = url.path.withCString { path in
                setxattr(path, name, payload, payload.count, 0, 0)
            }
            #expect(status == 0)

            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 0, length: 3)]))

            #expect(outcome.isClean)
            var buffer = [UInt8](repeating: 0, count: 8)
            let size = url.path.withCString { path in
                getxattr(path, name, &buffer, buffer.count, 0, 0)
            }
            #expect(size == payload.count)
            #expect(Array(buffer.prefix(payload.count)) == payload)
        }
    }

    @Test
    func rewritingASymlinkUpdatesTheTargetAndKeepsTheLink() throws {
        try withTempDir { dir in
            let target = dir.appending(path: "real.txt")
            let link = dir.appending(path: "link.txt")
            try write("foo", to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let outcome = FindFileRewriter.rewrite(try job(link, ranges: [NSRange(location: 0, length: 3)]))

            #expect(outcome.isClean)
            #expect(try text(of: target) == "quux")
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            #expect(destination == target.path)
        }
    }

    @Test
    func changedContentIsStaleAndLeavesBytesUntouched() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try write("bar bar", to: url)
            let before = try Data(contentsOf: url)

            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 4, length: 3)]))

            #expect(outcome == .stale)
            #expect(!outcome.isClean)
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test
    func missingFileFails() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "missing.txt")
            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 0, length: 3)]))
            #expect(outcome == .failed("Cannot read missing.txt"))
        }
    }

    @Test
    func nonUTF8FileFailsAndIsNotModified() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "latin.txt")
            let bytes = Data([0x66, 0x6F, 0x6F, 0xFF, 0xFE])
            try bytes.write(to: url)

            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 0, length: 3)]))

            #expect(outcome == .failed("Cannot read latin.txt"))
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test
    func readOnlyFileFailsWithoutChangingContent() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "locked.txt")
            try write("foo", to: url, permissions: 0o444)

            let outcome = FindFileRewriter.rewrite(try job(url, ranges: [NSRange(location: 0, length: 3)]))

            guard case .failed(let message) = outcome else {
                Issue.record("expected failure, got \(outcome)")
                return
            }
            #expect(message.hasPrefix("Cannot write locked.txt: "))
            #expect(try text(of: url) == "foo")
            #expect(try permissions(of: url) == 0o444)
        }
    }

    @Test
    func partiallyMatchingRangesReplaceWhatTheyCanAndReportMissing() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try write("foo foo", to: url)

            let outcome = FindFileRewriter.rewrite(
                try job(url, ranges: [NSRange(location: 0, length: 3), NSRange(location: 40, length: 3)])
            )

            guard case .replaced(let result) = outcome else {
                Issue.record("expected replaced, got \(outcome)")
                return
            }
            #expect(result.missing == 1)
            #expect(result.text == "quux foo")
            #expect(!outcome.isClean)
            #expect(try text(of: url) == "quux foo")
        }
    }

    @Test
    func bulkRewriteHandlesMoreJobsThanTheConcurrencyWidth() async throws {
        try await withTempDir { dir in
            var jobs: [FindReplaceJob] = []
            var urls: [URL] = []
            for index in 0..<40 {
                let url = dir.appending(path: "file-\(index).txt")
                try write("foo \(index) foo", to: url)
                urls.append(url)
                jobs.append(try job(url, replace: "n\(index)", ranges: [NSRange(location: 0, length: 3)]))
            }

            let outcomes = await FindFileRewriter.rewrite(jobs)

            #expect(outcomes.count == 40)
            for (index, url) in urls.enumerated() {
                #expect(try #require(outcomes.dropFirst(index).first).isClean)
                #expect(try text(of: url) == "n\(index) \(index) foo")
            }
        }
    }

    @Test
    func bulkRewriteReportsPerJobOutcomes() async throws {
        try await withTempDir { dir in
            let good = dir.appending(path: "good.txt")
            let stale = dir.appending(path: "stale.txt")
            try write("foo", to: good)
            try write("bar", to: stale)
            let jobs = [
                try job(good, ranges: [NSRange(location: 0, length: 3)]),
                try job(stale, ranges: [NSRange(location: 0, length: 3)]),
                try job(dir.appending(path: "missing.txt"), ranges: [NSRange(location: 0, length: 3)])
            ]

            let outcomes = await FindFileRewriter.rewrite(jobs)

            #expect(outcomes.count == 3)
            #expect(outcomes.first?.isClean == true)
            #expect(outcomes.dropFirst().first == .stale)
            #expect(outcomes.last == .failed("Cannot read missing.txt"))
        }
    }

    @Test
    func bulkRewriteOfNoJobsIsEmpty() async {
        let outcomes = await FindFileRewriter.rewrite([FindReplaceJob]())
        #expect(outcomes.isEmpty)
    }

    @Test
    func failingWriterRestoresTheOriginalBytes() throws {
        try withTempDir { dir in
            struct WriteFailure: Error {}
            let url = dir.appending(path: "a.txt")
            try write("foo foo", to: url)
            let original = try Data(contentsOf: url)
            let garbage = Data([0x7A, 0x7A])

            let outcome = FindFileRewriter.rewrite(
                try job(url, ranges: [NSRange(location: 0, length: 3)]),
                writer: { handle, _ in
                    try handle.write(contentsOf: garbage)
                    throw WriteFailure()
                }
            )

            guard case .failed(let message) = outcome else {
                Issue.record("expected failure, got \(outcome)")
                return
            }
            #expect(message.hasPrefix("Cannot write a.txt: "))
            #expect(try Data(contentsOf: url) == original)
        }
    }
}
