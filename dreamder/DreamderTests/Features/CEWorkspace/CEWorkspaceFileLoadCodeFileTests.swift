import Foundation
import Testing
@testable import Dreamder

private actor OpenGate {
    private var isOpen = false
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var hasEntered: Bool { entered }

    func pass() async {
        entered = true
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

private struct OpenFailure: Error {}

@MainActor
private final class FailureCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct CEWorkspaceFileLoadCodeFileTests {
    private func write(byteCount: Int, in directory: URL, name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data(repeating: UInt8(ascii: "x"), count: byteCount).write(to: url)
        return url
    }

    private func gatedLoader(_ gate: OpenGate) -> CodeFileDiskLoader.Loader {
        { url, fileTypeName in
            await gate.pass()
            return try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
        }
    }

    private func discard(_ document: CodeFileDocument?) {
        document?.close()
    }

    @Test
    func aFileAtTheSynchronousLimitIsReadBeforeLoadCodeFileReturns() throws {
        try withTempDir { dir in
            let url = try write(byteCount: FileSizeLimit.synchronousOpen, in: dir, name: "at-limit.txt")
            let file = CEWorkspaceFile(url: url)
            let refusing: CodeFileDiskLoader.Loader = { _, _ in throw OpenFailure() }

            try file.loadCodeFile(loader: refusing)
            defer { discard(file.fileDocument) }

            let document = try #require(file.fileDocument)
            #expect(!document.isLoading)
            #expect(document.loadTask == nil)
            #expect(document.content?.length == FileSizeLimit.synchronousOpen)
            #expect(DreamderDocumentController.shared.documents.contains { $0 === document })
        }
    }

    @Test
    func aFileJustAboveTheSynchronousLimitLoadsInTheBackground() async throws {
        try await withTempDir { dir in
            let size = FileSizeLimit.synchronousOpen + 1
            let url = try write(byteCount: size, in: dir, name: "above-limit.txt")
            let file = CEWorkspaceFile(url: url)
            let gate = OpenGate()

            try file.loadCodeFile(loader: gatedLoader(gate))
            let document = try #require(file.fileDocument)
            defer { discard(document) }

            #expect(document.isLoading)
            #expect(document.content == nil)
            #expect(document.loadTask != nil)
            #expect(DreamderDocumentController.shared.documents.contains { $0 === document })
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            var ticks = 0
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(5))
                ticks += 1
            }
            #expect(ticks == 5)
            #expect(document.isLoading)
            #expect(document.content == nil)

            await gate.open()
            try await eventually(timeout: .seconds(20)) { !document.isLoading }

            #expect(document.content?.length == size)
            #expect(file.fileDocument === document)
        }
    }

    @Test
    func closingTheDocumentWhileItLoadsCancelsTheLoad() async throws {
        try await withTempDir { dir in
            let url = try write(byteCount: FileSizeLimit.synchronousOpen + 1, in: dir, name: "closed.txt")
            let file = CEWorkspaceFile(url: url)
            let gate = OpenGate()
            try file.loadCodeFile(loader: gatedLoader(gate))
            let document = try #require(file.fileDocument)
            let load = try #require(document.loadTask)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            document.close()
            file.fileDocument = nil
            #expect(document.loadTask == nil)
            await gate.open()
            await load.value

            #expect(document.content == nil)
            #expect(!DreamderDocumentController.shared.documents.contains { $0 === document })
        }
    }

    @Test
    func aFailedBackgroundLoadClearsTheFilesDocumentAndClosesIt() async throws {
        try await withTempDir { dir in
            let url = try write(byteCount: FileSizeLimit.synchronousOpen + 1, in: dir, name: "failing.txt")
            let file = CEWorkspaceFile(url: url)
            let counter = FailureCounter()
            let failing: CodeFileDiskLoader.Loader = { _, _ in
                await counter.record()
                throw OpenFailure()
            }

            try file.loadCodeFile(loader: failing)
            let document = try #require(file.fileDocument)
            let load = try #require(document.loadTask)
            await load.value

            #expect(counter.count == 1)
            #expect(file.fileDocument == nil)
            #expect(!document.isLoading)
            #expect(!DreamderDocumentController.shared.documents.contains { $0 === document })
        }
    }

    @Test
    func aMissingFileStillThrowsFromTheSynchronousPath() throws {
        try withTempDir { dir in
            let file = CEWorkspaceFile(url: dir.appending(path: "missing.txt"))

            #expect(throws: (any Error).self) { try file.loadCodeFile() }
            #expect(file.fileDocument == nil)
        }
    }
}
