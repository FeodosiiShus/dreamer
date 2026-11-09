import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorDragDropTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources", "Empty"]
    private static let files = ["a.txt", "b.md", "Sources/main.swift"]

    @Test
    func validateDropOnlyAcceptsRowTargets() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")
            let moving = harness.dropInfo(urls: [a.url])
            let copying = harness.dropInfo(urls: [a.url], mask: .copy)

            let onFolder = harness.dropOperation(for: moving, proposedItem: sources, proposedChildIndex: -1)
            let copyOnFolder = harness.dropOperation(for: copying, proposedItem: sources, proposedChildIndex: -1)
            let onFile = harness.dropOperation(for: moving, proposedItem: a, proposedChildIndex: -1)
            let between = harness.dropOperation(for: moving, proposedItem: sources, proposedChildIndex: 0)
            let onStranger = harness.dropOperation(for: moving, proposedItem: "stranger", proposedChildIndex: -1)
            let onNothing = harness.dropOperation(for: moving, proposedItem: nil, proposedChildIndex: -1)

            #expect(onFolder == .move)
            #expect(copyOnFolder == .copy)
            #expect(onFile == .move)
            #expect(between == [])
            #expect(onStranger == [])
            #expect(onNothing == [])
        }
    }

    @Test
    func droppingAFileOnAFolderMovesItAndOpensTheMovedFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")
            let info = harness.dropInfo(urls: [a.url])

            let accepted = harness.acceptDrop(info, onto: sources)

            #expect(accepted)
            #expect(harness.exists("Sources/a.txt"))
            #expect(!harness.exists("a.txt"))
            #expect(harness.editor.tabs.contains { $0.file.url.lastPathComponent == "a.txt" })
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "a.txt")
        }
    }

    @Test
    func droppingAFolderOnAFolderMovesTheWholeFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let empty = try harness.file("Empty")
            let info = harness.dropInfo(urls: [empty.url])

            let accepted = harness.acceptDrop(info, onto: sources)

            #expect(accepted)
            #expect(harness.exists("Sources/Empty"))
            #expect(!harness.exists("Empty"))
        }
    }

    @Test
    func droppingWithTheCopyMaskCopiesTheFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")
            let info = harness.dropInfo(urls: [a.url], mask: .copy)

            let accepted = harness.acceptDrop(info, onto: sources)

            #expect(accepted)
            #expect(harness.exists("Sources/a.txt"))
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func droppingAFileIntoItsOwnParentIsRejected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let info = harness.dropInfo(urls: [a.url])

            let accepted = harness.acceptDrop(info, onto: harness.rootFile)

            #expect(!accepted)
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func droppingExternalFilesMovesOrCopiesThemIntoTheWorkspace() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let outside = try makeTemporaryDirectory(label: "ProjectNavigatorExternal")
            defer { removeTemporaryDirectory(outside) }
            let moved = outside.appending(path: "moved-in.txt")
            let copied = outside.appending(path: "copied-in.txt")
            try "moved".write(to: moved, atomically: true, encoding: .utf8)
            try "copied".write(to: copied, atomically: true, encoding: .utf8)
            let sources = try harness.file("Sources")

            let moveAccepted = harness.acceptDrop(harness.dropInfo(urls: [moved]), onto: sources)
            let copyAccepted = harness.acceptDrop(harness.dropInfo(urls: [copied], mask: .copy), onto: sources)

            #expect(moveAccepted)
            #expect(copyAccepted)
            #expect(try harness.contents("Sources/moved-in.txt") == "moved")
            #expect(!FileManager.default.fileExists(atPath: moved.path))
            #expect(try harness.contents("Sources/copied-in.txt") == "copied")
            #expect(FileManager.default.fileExists(atPath: copied.path))
        }
    }

    @Test
    func dropsWithoutAWorkspaceDestinationOrURLsChangeNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let info = harness.dropInfo(urls: [a.url])
            let empty = harness.dropInfo(urls: [])
            let sources = try harness.file("Sources")

            let withoutItem = harness.acceptDrop(info, onto: nil)
            let onStranger = harness.acceptDrop(info, onto: "stranger")
            let withoutURLs = harness.controller.acceptDrop(of: nil, sourceOperationMask: .move, onto: sources)
            _ = harness.acceptDrop(empty, onto: sources)

            #expect(!withoutItem)
            #expect(!onStranger)
            #expect(!withoutURLs)
            #expect(harness.exists("a.txt"))
            #expect(try harness.names(in: "Sources") == ["main.swift"])
        }
    }

    @Test
    func existingDestinationIsReplacedWhenTheUserConfirms() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["Sources/a.txt"]) { harness in
            try harness.write("Sources/a.txt", "old")
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [a.url]), onto: sources)

            #expect(accepted)
            #expect(asked == ["a.txt"])
            #expect(try harness.contents("Sources/a.txt") == "content of a.txt\n")
            #expect(!harness.exists("a.txt"))
        }
    }

    @Test
    func existingDestinationIsKeptWhenTheUserDeclines() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["Sources/a.txt"]) { harness in
            try harness.write("Sources/a.txt", "old")
            harness.controller.confirmReplace = { _ in false }
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [a.url]), onto: sources)

            #expect(!accepted)
            #expect(try harness.contents("Sources/a.txt") == "old")
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func theDefaultReplaceDialogIsPresentedAndCancelsInHeadlessMode() async throws {
        try await Harness.run(folders: Self.folders, files: ["headless-replace.txt", "Sources/headless-replace.txt"]) {
            harness in
            let sources = try harness.file("Sources")
            let dropped = try harness.file("headless-replace.txt")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [dropped.url]), onto: sources)

            #expect(!accepted)
            #expect(DreamderHeadless.suppressedModals.contains {
                $0.contains("A file or folder with the name headless-replace.txt already exists")
            })
            #expect(harness.exists("headless-replace.txt"))
        }
    }

    @Test
    func replaceDialogReportsFalseWhenNothingConfirms() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(!harness.controller.replaceFileDialog(fileName: "direct-dialog-call.txt"))
            #expect(DreamderHeadless.suppressedModals.contains {
                $0.contains("direct-dialog-call.txt already exists")
            })
        }
    }

    @Test
    func replacementFailureAbortsTheDrop() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["Sources/a.txt"]) { harness in
            harness.controller.confirmReplace = { _ in true }
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")
            try harness.lock("Sources")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [a.url]), onto: sources)

            #expect(!accepted)
            #expect(harness.exists("Sources/a.txt"))
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func theOutlineDelegateReadsOperationMaskAndDroppedURLsFromTheDraggingInfo() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")
            let copying = ProjectNavigatorFakeDraggingInfo(urls: [a.url], operationMask: .copy)
            defer { copying.releasePasteboard() }

            let proposed = harness.controller.outlineView(
                harness.outlineView,
                validateDrop: copying,
                proposedItem: sources,
                proposedChildIndex: -1
            )
            let accepted = harness.controller.outlineView(
                harness.outlineView,
                acceptDrop: copying,
                item: sources,
                childIndex: -1
            )

            #expect(proposed == .copy)
            #expect(accepted)
            #expect(try harness.contents("Sources/a.txt") == "content of a.txt\n")
            #expect(harness.exists("a.txt"))
        }
    }
}

@MainActor
final class ProjectNavigatorFakeDraggingInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard
    private let operationMask: NSDragOperation

    init(urls: [URL], operationMask: NSDragOperation) {
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        board.clearContents()
        _ = board.writeObjects(urls.map { $0 as NSURL })
        self.pasteboard = board
        self.operationMask = operationMask
        super.init()
    }

    func releasePasteboard() {
        pasteboard.releaseGlobally()
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { operationMask }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
