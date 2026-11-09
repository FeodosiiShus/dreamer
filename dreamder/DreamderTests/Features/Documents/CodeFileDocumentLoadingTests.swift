import Foundation
import Testing
@testable import Dreamder

private actor LoadingGate {
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

private struct LoadingFailure: Error, Equatable {}

@MainActor
private final class FailureRecorder {
    private(set) var errors: [LoadingFailure] = []
    private(set) var all: [any Error] = []

    var count: Int { all.count }

    func record(_ error: any Error) {
        all.append(error)
        if let failure = error as? LoadingFailure {
            errors.append(failure)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileDocumentLoadingTests {
    private static let plainText = "public.plain-text"

    private func write(_ text: String, in directory: URL, name: String = "loading.txt") throws -> URL {
        let url = directory.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func gatedLoader(_ gate: LoadingGate) -> CodeFileDiskLoader.Loader {
        { url, fileTypeName in
            await gate.pass()
            return try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
        }
    }

    private func modificationDate(of url: URL) throws -> Date? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attributes[.modificationDate] as? Date
    }

    @Test
    func theContentIsReadOffTheMainActorAndAppliedWhenReady() async throws {
        try await withTempDir { dir in
            let url = try write("a {\n  b\n  c\n}\n", in: dir)
            let expectedDate = try modificationDate(of: url)
            let gate = LoadingGate()
            let recorder = FailureRecorder()
            let document = CodeFileDocument.loading(
                contentsOf: url,
                ofType: Self.plainText,
                loader: gatedLoader(gate)
            ) { recorder.record($0) }
            defer { document.close() }

            #expect(document.isLoading)
            #expect(document.content == nil)
            #expect(document.loadTask != nil)
            #expect(document.fileURL == url)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            var ticks = 0
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(5))
                ticks += 1
            }
            #expect(ticks == 5)
            #expect(document.isLoading)
            #expect(document.content == nil)
            #expect(!document.applySaveActions())

            await gate.open()
            try await eventually(timeout: .seconds(20)) { !document.isLoading }

            #expect(document.content?.string == "a {\n  b\n  c\n}\n")
            #expect(document.detectedIndent == .spaces(size: 2))
            #expect(document.sourceEncoding == .utf8)
            #expect(document.loadTask == nil)
            #expect(document.fileModificationDate == expectedDate)
            #expect(recorder.all.isEmpty)
        }
    }

    @Test
    func closingTheDocumentCancelsTheLoadAndLeavesNoTaskBehind() async throws {
        try await withTempDir { dir in
            let url = try write("text\n", in: dir)
            let gate = LoadingGate()
            let recorder = FailureRecorder()
            let document = CodeFileDocument.loading(
                contentsOf: url,
                ofType: Self.plainText,
                loader: gatedLoader(gate)
            ) { recorder.record($0) }
            let load = try #require(document.loadTask)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            document.close()
            #expect(document.loadTask == nil)
            await gate.open()
            await load.value

            #expect(document.content == nil)
            #expect(recorder.all.isEmpty)
        }
    }

    @Test
    func aFailedLoadIsReportedOnceAndTheDocumentIsClosed() async throws {
        try await withTempDir { dir in
            let url = try write("text\n", in: dir)
            let recorder = FailureRecorder()
            let closed = CloseNotificationCounter(for: url)
            let document = CodeFileDocument.loading(
                contentsOf: url,
                ofType: Self.plainText,
                loader: { _, _ in throw LoadingFailure() },
                onFailure: { recorder.record($0) }
            )
            let load = try #require(document.loadTask)

            await load.value

            #expect(recorder.errors == [LoadingFailure()])
            #expect(recorder.count == 1)
            #expect(!document.isLoading)
            #expect(document.loadTask == nil)
            #expect(document.content == nil)
            #expect(closed.count == 1)
        }
    }

    @Test
    func aChangeOnDiskWhileLoadingIsReloadedRightAfterwards() async throws {
        try await withTempDir { dir in
            let url = try write("old\n", in: dir)
            let gate = LoadingGate()
            let document = CodeFileDocument.loading(
                contentsOf: url,
                ofType: Self.plainText,
                loader: { url, fileTypeName in
                    let loaded = try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
                    await gate.pass()
                    return loaded
                },
                onFailure: { _ in }
            )
            defer { document.close() }
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }
            try "new\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 5_000)],
                ofItemAtPath: url.path(percentEncoded: false)
            )

            document.presentedItemDidChange()
            #expect(document.reloadTask == nil)
            await gate.open()

            try await eventually(timeout: .seconds(20)) { document.content?.string == "new\n" }
            #expect(document.fileModificationDate == Date(timeIntervalSince1970: 5_000))
        }
    }

    @Test
    func readingIsCancelledBeforeTheFileIsTouchedWhenTheTaskIsCancelled() async throws {
        try await withTempDir { dir in
            let url = try write("text\n", in: dir)
            let task = Task {
                while !Task.isCancelled {
                    await Task.yield()
                }
                return try await CodeFileDiskLoader.read(from: url, fileTypeName: Self.plainText)
            }

            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }
}

@MainActor
private final class CloseNotificationCounter {
    private(set) var count = 0
    private var token: NSObjectProtocol?

    init(for url: URL) {
        token = NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didCloseNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let closed = notification.object as? URL
            MainActor.assumeIsolated {
                if closed == url {
                    self?.count += 1
                }
            }
        }
    }

    isolated deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
