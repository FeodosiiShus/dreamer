import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiffViewerWindowCoverageTests {
    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeModel(_ dir: URL, files names: [String] = ["first.txt"]) async throws -> DiffViewerViewModel {
        _ = try await GitMergeFixture(root: dir)
        for name in names {
            try "text of \(name)\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        }
        let repo = try repository(dir)
        let files = names.map {
            repo.workingTreeRequest(status: .untracked, path: $0, originalPath: nil, ref: "HEAD")
        }
        return DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)
    }

    @Test
    func controllerConfiguresTheWindowAndLoadsTheFirstFile() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir)
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            defer { window.close() }

            #expect(window.title == "first.txt (HEAD vs Local)")
            #expect(window.appearance?.name == .darkAqua)
            #expect(window.styleMask == [.titled, .closable, .miniaturizable, .resizable])
            #expect(window.minSize == NSSize(width: 640, height: 360))
            #expect(window.isReleasedWhenClosed == false)
            #expect(window.delegate === controller)
            #expect(window.contentView != nil)

            try await eventually { model.diff != nil }
            #expect(model.differenceSummary == "1 difference")
        }
    }

    @Test
    func windowRendersTheDiffView() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir)
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            defer { window.close() }
            window.orderFront(nil)

            try await eventually { model.diff != nil }
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(window.contentView?.bounds.isEmpty == false)
        }
    }

    @Test
    func updateFilesChangesTheSelectionAndTheWindowTitle() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir, files: ["first.txt", "second.txt"])
            let repo = try repository(dir)
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            defer { window.close() }
            try await eventually { model.diff != nil }

            let replacement = repo.workingTreeRequest(status: .untracked, path: "second.txt", originalPath: nil, ref: "HEAD")
            controller.update(files: [replacement])
            try await eventually { window.title == "second.txt (HEAD vs Local)" }
            #expect(model.selectedID == "second.txt")
        }
    }

    @Test
    func reloadReloadsTheSelectedFile() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir)
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            defer { window.close() }
            try await eventually { model.diff != nil }

            try "changed\nagain\nand again\n".write(
                to: dir.appending(path: "first.txt"),
                atomically: true,
                encoding: .utf8
            )
            controller.reload()
            try await eventually { model.diff?.rightLines.count == 3 }
        }
    }

    @Test
    func placeCentersOnTheParentWindowOrTheMainScreen() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir)
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            defer { window.close() }
            let parent = HostedViewFixture.host(size: NSSize(width: 800, height: 500)) { EmptyView() }
            defer { parent.close() }
            let size = window.frame.size

            controller.place(relativeTo: parent.window)
            #expect(window.frame.size == size)
            if let screen = parent.window.screen ?? NSScreen.main {
                #expect(window.frame.origin.x <= screen.visibleFrame.maxX - size.width - 12 + 0.5)
                #expect(window.frame.origin.y <= screen.visibleFrame.maxY - size.height - 12 + 0.5)
            }

            controller.place(relativeTo: nil)
            #expect(window.frame.size == size)
            if let screen = NSScreen.main {
                #expect(window.frame.origin.x <= screen.visibleFrame.maxX - size.width - 12 + 0.5)
                #expect(window.frame.origin.y <= screen.visibleFrame.maxY - size.height - 12 + 0.5)
            }
        }
    }

    @Test
    func closingTheWindowNotifiesTheOwnerAndStopsTitleUpdates() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir, files: ["first.txt", "second.txt"])
            let controller = DiffViewerWindowController(model: model)
            let window = try #require(controller.window)
            var closed = 0
            controller.onClose = { closed += 1 }
            try await eventually { model.diff != nil }

            window.close()
            #expect(closed == 1)

            let titleAtClose = window.title
            await model.select("second.txt")
            try await Task.sleep(for: .milliseconds(100))
            #expect(window.title == titleAtClose)
            #expect(model.title == "second.txt (HEAD vs Local)")
        }
    }

    @Test
    func releasedControllerCancelsItsTitleObservation() async throws {
        try await withTempDir { dir in
            let model = try await makeModel(dir)
            weak var released: DiffViewerWindowController?
            do {
                let controller = DiffViewerWindowController(model: model)
                released = controller
                controller.window?.close()
            }
            try await eventually(timeout: .seconds(10)) { released == nil }
        }
    }

    @Test
    func controllerCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        #expect(DiffViewerWindowController(coder: decoder) == nil)
    }
}
