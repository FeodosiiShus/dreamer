import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderDocumentControllerFilePanelTests {
    private func sharedController() throws -> DreamderDocumentController {
        try #require(DreamderDocumentController.shared as? DreamderDocumentController)
    }

    private func openFileNames(in workspace: WorkspaceDocument) -> [String] {
        let files = workspace.editorManager?.editorLayout.gatherOpenFiles() ?? []
        return files.map(\.name).sorted()
    }

    @Test
    func theDefaultPresenterIsTheSystemOne() throws {
        let controller = try sharedController()

        #expect(controller.filePanels is SystemFilePanels)
    }

    @Test
    func theDefaultPresenterCancelsEveryDialogInHeadlessMode() async throws {
        try #require(DreamderHeadless.isEnabled)
        let controller = try sharedController()

        controller.newDocument(nil)
        let created = await controller.createAndOpenNewDocument()
        controller.openDocument(nil)

        #expect(!created)
    }

    @Test
    func aCancelledSaveDialogCreatesNothing() async throws {
        let controller = try sharedController()
        let panels = FakeFilePanels()

        controller.createNewDocument(panels: panels)
        let created = await controller.createAndOpenNewDocument(panels: panels)

        #expect(panels.saveRequests == [SavePanelRequest(), SavePanelRequest()])
        #expect(!created)
    }

    @Test
    func aDestinationInAMissingFolderIsNotCreated() async throws {
        try await withTempDir { directory in
            let controller = try sharedController()
            let missing = directory.appending(path: "missing/New.txt")
            let panels = FakeFilePanels(saveLocation: missing)

            controller.createNewDocument(panels: panels)
            let created = await controller.createAndOpenNewDocument(panels: panels)

            #expect(FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)) == false)
            #expect(!created)
        }
    }

    @Test
    func newFilesAreCreatedAndOpenedInTheWorkspaceThatContainsThem() async throws {
        try await withTempDir { directory in
            let workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
            defer { workspace.close() }
            let controller = try sharedController()
            controller.addDocument(workspace)
            let first = directory.appending(path: "First.txt")
            let second = directory.appending(path: "Second.txt")
            let panels = FakeFilePanels(saveLocation: first)

            controller.createNewDocument(panels: panels)
            panels.chosenSaveLocation = second
            let created = await controller.createAndOpenNewDocument(panels: panels)

            #expect(created)
            #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
            #expect(openFileNames(in: workspace) == ["First.txt", "Second.txt"])
        }
    }

    @Test
    func theOpenActionAsksForAFileOrWorkspaceAndStopsWhenCancelled() throws {
        let controller = try sharedController()
        let panels = FakeFilePanels()

        controller.openDocument(panels: panels)

        let request = try #require(panels.openRequests.first)
        #expect(panels.openRequests.count == 1)
        #expect(request.title == "Open Workspace or File")
        #expect(request.canChooseFiles)
        #expect(request.canChooseDirectories)
        #expect(request.allowsMultipleSelection == false)
    }
}
