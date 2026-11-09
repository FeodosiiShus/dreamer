import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

@MainActor
private final class FakeOpenPanel: OpenPanelConfiguring {
    var title: String!
    var prompt: String!
    var message: String!
    var allowedContentTypes: [UTType] = []
    var showsHiddenFiles = false
    var canChooseFiles = false
    var canChooseDirectories = false
    var allowsMultipleSelection = false
    var urls: [URL] = []
    var response: NSApplication.ModalResponse = .OK
    private(set) var runs = 0

    func runModal() -> NSApplication.ModalResponse {
        runs += 1
        return response
    }
}

@MainActor
private final class FakeSavePanel: SavePanelConfiguring {
    var title: String!
    var prompt: String!
    var message: String!
    var nameFieldLabel: String!
    var nameFieldStringValue = ""
    var allowedContentTypes: [UTType] = []
    var canCreateDirectories = false
    var showsHiddenFiles = false
    var showsTagField = false
    var url: URL?
    var response: NSApplication.ModalResponse = .OK
    private(set) var runs = 0

    func runModal() -> NSApplication.ModalResponse {
        runs += 1
        return response
    }
}

@MainActor
@Suite(.uiGate)
struct SystemFilePanelsTests {
    private let chosen = URL(fileURLWithPath: "/tmp/dreamder-chosen.txt")

    @Test
    func theOpenPanelIsConfiguredFromTheRequestAndReturnsTheChosenFiles() {
        let panel = FakeOpenPanel()
        panel.urls = [chosen]
        let request = OpenPanelRequest(
            title: "Open",
            prompt: "Choose",
            message: "Pick a file",
            allowedContentTypes: [.plainText],
            canChooseFiles: false,
            canChooseDirectories: true,
            allowsMultipleSelection: true,
            showsHiddenFiles: true
        )

        let urls = SystemFilePanels().run(request, on: panel)

        #expect(urls == [chosen])
        #expect(panel.runs == 1)
        #expect(panel.title == "Open")
        #expect(panel.prompt == "Choose")
        #expect(panel.message == "Pick a file")
        #expect(panel.allowedContentTypes == [.plainText])
        #expect(!panel.canChooseFiles)
        #expect(panel.canChooseDirectories)
        #expect(panel.allowsMultipleSelection)
        #expect(panel.showsHiddenFiles)
    }

    @Test
    func theOpenPanelKeepsItsOwnTextsWhenTheRequestHasNone() {
        let panel = FakeOpenPanel()

        _ = SystemFilePanels().run(OpenPanelRequest(), on: panel)

        #expect(panel.title == nil)
        #expect(panel.prompt == nil)
        #expect(panel.message == nil)
        #expect(panel.canChooseFiles)
    }

    @Test
    func aCancelledOpenPanelChoosesNothing() {
        let panel = FakeOpenPanel()
        panel.urls = [chosen]
        panel.response = .cancel

        #expect(SystemFilePanels().run(OpenPanelRequest(), on: panel).isEmpty)
    }

    @Test
    func theSavePanelIsConfiguredFromTheRequestAndReturnsTheChosenLocation() {
        let panel = FakeSavePanel()
        panel.url = chosen
        let request = SavePanelRequest(
            title: "Save",
            prompt: "Store",
            message: "Pick a place",
            nameFieldLabel: "Name:",
            nameFieldStringValue: "notes.md",
            allowedContentTypes: [.plainText],
            canCreateDirectories: false,
            showsHiddenFiles: true,
            showsTagField: false
        )

        let location = SystemFilePanels().run(request, on: panel)

        #expect(location == chosen)
        #expect(panel.runs == 1)
        #expect(panel.title == "Save")
        #expect(panel.prompt == "Store")
        #expect(panel.message == "Pick a place")
        #expect(panel.nameFieldLabel == "Name:")
        #expect(panel.nameFieldStringValue == "notes.md")
        #expect(panel.allowedContentTypes == [.plainText])
        #expect(!panel.canCreateDirectories)
        #expect(panel.showsHiddenFiles)
        #expect(!panel.showsTagField)
    }

    @Test
    func theSavePanelKeepsItsOwnTextsWhenTheRequestHasNone() {
        let panel = FakeSavePanel()

        _ = SystemFilePanels().run(SavePanelRequest(), on: panel)

        #expect(panel.title == nil)
        #expect(panel.prompt == nil)
        #expect(panel.message == nil)
        #expect(panel.nameFieldLabel == nil)
        #expect(panel.canCreateDirectories)
        #expect(panel.showsTagField)
    }

    @Test
    func aCancelledSavePanelChoosesNoLocation() {
        let panel = FakeSavePanel()
        panel.url = chosen
        panel.response = .cancel

        #expect(SystemFilePanels().run(SavePanelRequest(), on: panel) == nil)
    }

    @Test
    func outsideHeadlessModeChoosingFilesRunsAPanelFromTheFactory() {
        let panel = FakeOpenPanel()
        panel.urls = [chosen]
        let panels = SystemFilePanels(makeOpenPanel: { panel }, isHeadless: { false })

        let urls = panels.chooseFiles(OpenPanelRequest(message: "Open", canChooseDirectories: true))

        #expect(urls == [chosen])
        #expect(panel.runs == 1)
        #expect(panel.message == "Open")
        #expect(panel.canChooseDirectories)
    }

    @Test
    func outsideHeadlessModeChoosingASaveLocationRunsAPanelFromTheFactory() {
        let panel = FakeSavePanel()
        panel.url = chosen
        let panels = SystemFilePanels(makeSavePanel: { panel }, isHeadless: { false })

        let location = panels.chooseSaveLocation(SavePanelRequest(nameFieldStringValue: "Untitled"))

        #expect(location == chosen)
        #expect(panel.runs == 1)
        #expect(panel.nameFieldStringValue == "Untitled")
    }

    @Test
    func headlessModeSuppressesBothPanelsWithoutCreatingThem() {
        var created = 0
        let panels = SystemFilePanels(
            makeOpenPanel: { created += 1; return FakeOpenPanel() },
            makeSavePanel: { created += 1; return FakeSavePanel() },
            isHeadless: { true }
        )

        #expect(panels.chooseFiles(OpenPanelRequest(message: "suppressed open")).isEmpty)
        #expect(panels.chooseSaveLocation(SavePanelRequest(message: "suppressed save")) == nil)
        #expect(created == 0)
        #expect(DreamderHeadless.suppressedModals.suffix(2) == ["suppressed open", "suppressed save"])
    }
}
