import AppKit
import Combine
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ReplaceInOpenBuffersTests {
    private static let original = "let needle = 1\nlet needle = 2\n"
    private static let replaced = "let string-x = 1\nlet string-x = 2\n"
    private static let mixedFailure = "1 successfully updated, 1 errors occurred. Please check logs for more information."

    @MainActor
    private final class Session {
        let workspace: WorkspaceDocument
        let state: FindStateSupport.State
        let fixture: HostedSourceEditorFixture
        let directory: URL
        private(set) var hosted: HostedSourceEditor?
        private var editedSubscription: AnyCancellable?

        init(
            workspace: WorkspaceDocument,
            state: FindStateSupport.State,
            fixture: HostedSourceEditorFixture,
            directory: URL
        ) {
            self.workspace = workspace
            self.state = state
            self.fixture = fixture
            self.directory = directory
        }

        var document: CodeFileDocument { fixture.document }

        var textView: TextView? { document.attachedTextView }

        static func make(in directory: URL, attached: Bool) async throws -> Session {
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "open.txt",
                typeIdentifier: "public.plain-text",
                contents: ReplaceInOpenBuffersTests.original
            )
            fixture.document.autosavingInPlace = { false }
            try FindStateSupport.write("needle closed\n", "closed.txt", in: directory)
            let (workspace, state) = try await FindStateSupport.prepare(in: directory)
            let session = Session(workspace: workspace, state: state, fixture: fixture, directory: directory)
            fixture.editorInstance.file.fileDocument = fixture.document
            let editor = try #require(workspace.editorManager?.activeEditor)
            editor.tabs.append(fixture.editorInstance)
            editor.setSelectedTab(fixture.editorInstance.file)
            try await eventually { fixture.document.content != nil }
            state.setReplaceMode(true)
            state.replaceText = "string-x"
            try await FindStateSupport.settle()
            if attached {
                session.attach()
                try await eventually { fixture.document.attachedTextView != nil }
            }
            return session
        }

        private func attach() {
            let document = fixture.document
            hosted = fixture.host(
                coordinators: [document.contentCoordinator, document.textViewBinder],
                size: NSSize(width: 900, height: 600)
            )
            editedSubscription = document.contentCoordinator.textUpdatePublisher
                .sink { [weak document] _ in document?.updateChangeCount(.changeDone) }
        }

        func close() {
            hosted?.close()
            workspace.close()
        }
    }

    @Test
    func attachedBufferIsEditedThroughTheTextViewAndUndoneInOneStep() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: true)
            defer { session.close() }
            let textView = try #require(session.textView)
            textView.selectionManager.setSelectedRanges([
                NSRange(location: 0, length: 0),
                NSRange(location: Self.original.utf16.count, length: 0)
            ])
            await session.state.search("needle")
            #expect(session.state.searchResultsFileCount == 2)

            await session.state.replaceAll()

            #expect(textView.string == Self.replaced)
            #expect(session.document.content?.string == Self.replaced)
            #expect(try FindStateSupport.read("open.txt", in: dir) == Self.original)
            #expect(try FindStateSupport.read("closed.txt", in: dir) == "string-x closed\n")
            #expect(session.state.findNavigatorStatus == .replaced(updatedFiles: 2))
            try await eventually { session.document.isDocumentEdited }
            #expect(
                textView.selectionManager.textSelections.map(\.range) == [
                    NSRange(location: 0, length: 0),
                    NSRange(location: Self.replaced.utf16.count, length: 0)
                ]
            )

            let undoManager = try #require(textView.undoManager)
            undoManager.undo()
            try await eventually { textView.string == Self.original }
            #expect(session.document.content?.string == Self.original)
        }
    }

    @Test
    func unattachedOpenDocumentIsEditedInItsStorage() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: false)
            defer { session.close() }
            #expect(session.document.attachedTextView == nil)
            #expect(!session.document.isDocumentEdited)
            await session.state.search("needle")

            await session.state.replaceAll()

            #expect(session.document.content?.string == Self.replaced)
            #expect(session.document.isDocumentEdited)
            #expect(try FindStateSupport.read("open.txt", in: dir) == Self.original)
            #expect(try FindStateSupport.read("closed.txt", in: dir) == "string-x closed\n")
            #expect(session.state.findNavigatorStatus == .replaced(updatedFiles: 2))
            #expect(session.state.searchResult.isEmpty)
        }
    }

    @Test
    func replacingOneMatchInAnOpenBufferRebasesTheOthers() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: false)
            defer { session.close() }
            await session.state.search("needle")
            let first = try #require(FindStateSupport.matches("open.txt", in: session.state).first)

            await session.state.replace(first)

            #expect(session.document.content?.string == "let string-x = 1\nlet needle = 2\n")
            let remaining = try #require(FindStateSupport.matches("open.txt", in: session.state).first)
            #expect(remaining.usage?.range == NSRange(location: 21, length: 6))
            #expect(remaining.usage?.start == FindTextPosition(line: 2, column: 5))
            #expect(remaining.lineContent == "let needle = 2")
            #expect(session.state.findNavigatorStatus == .found)

            await session.state.replace(remaining)

            #expect(session.document.content?.string == Self.replaced)
            #expect(session.state.searchResult.map(\.file.name) == ["closed.txt"])
        }
    }

    @Test
    func unsavedBufferTextIsSearchedAndReplacedInTheBuffer() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: false)
            defer { session.close() }
            let storage = try #require(session.document.content)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "unsaved needle\nx\n")
            session.document.updateChangeCount(.changeDone)

            await session.state.search("needle")
            let match = try #require(FindStateSupport.matches("open.txt", in: session.state).first)
            #expect(match.lineContent == "unsaved needle")
            #expect(match.usage?.range == NSRange(location: 8, length: 6))

            await session.state.replaceAll()

            #expect(session.document.content?.string == "unsaved string-x\nx\n")
            #expect(try FindStateSupport.read("open.txt", in: dir) == Self.original)
        }
    }

    @Test
    func aBufferChangedAfterTheSearchIsStaleWhileClosedFilesStillUpdate() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: false)
            defer { session.close() }
            await session.state.search("needle")
            let storage = try #require(session.document.content)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "nothing\n")

            await session.state.replaceAll()

            #expect(session.document.content?.string == "nothing\n")
            #expect(try FindStateSupport.read("closed.txt", in: dir) == "string-x closed\n")
            #expect(session.state.searchResult.isEmpty)
            #expect(session.state.findNavigatorStatus == .failed(errorMessage: Self.mixedFailure))
        }
    }

    @Test
    func aReadOnlyTextViewFailsAndKeepsItsMatches() async throws {
        try await withTempDir { dir in
            let session = try await Session.make(in: dir, attached: true)
            defer { session.close() }
            let textView = try #require(session.textView)
            await session.state.search("needle")
            textView.isEditable = false

            await session.state.replaceAll()

            #expect(textView.string == Self.original)
            #expect(session.document.content?.string == Self.original)
            #expect(try FindStateSupport.read("closed.txt", in: dir) == "string-x closed\n")
            #expect(session.state.searchResult.map(\.file.name) == ["open.txt"])
            #expect(session.state.searchResultsCount == 2)
            #expect(session.state.findNavigatorStatus == .found)
            #expect(session.state.replaceNotice == Self.mixedFailure)
        }
    }
}
