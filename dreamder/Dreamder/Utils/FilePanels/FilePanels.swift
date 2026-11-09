import AppKit
import UniformTypeIdentifiers

nonisolated struct OpenPanelRequest: Equatable, Sendable {
    var title: String?
    var prompt: String?
    var message: String?
    var allowedContentTypes: [UTType] = []
    var canChooseFiles = true
    var canChooseDirectories = false
    var allowsMultipleSelection = false
    var showsHiddenFiles = false

    var summary: String { message ?? title ?? prompt ?? "" }
}

nonisolated struct SavePanelRequest: Equatable, Sendable {
    var title: String?
    var prompt: String?
    var message: String?
    var nameFieldLabel: String?
    var nameFieldStringValue = ""
    var allowedContentTypes: [UTType] = []
    var canCreateDirectories = true
    var showsHiddenFiles = false
    var showsTagField = true

    var summary: String { message ?? title ?? prompt ?? "" }
}

@MainActor
protocol FilePanelPresenting {
    func chooseFiles(_ request: OpenPanelRequest) -> [URL]
    func chooseSaveLocation(_ request: SavePanelRequest) -> URL?
}

@MainActor
protocol FilePanelConfiguring: AnyObject {
    var title: String! { get set }
    var prompt: String! { get set }
    var message: String! { get set }
    var allowedContentTypes: [UTType] { get set }
    var showsHiddenFiles: Bool { get set }

    func runModal() -> NSApplication.ModalResponse
}

@MainActor
protocol OpenPanelConfiguring: FilePanelConfiguring {
    var canChooseFiles: Bool { get set }
    var canChooseDirectories: Bool { get set }
    var allowsMultipleSelection: Bool { get set }
    var urls: [URL] { get }
}

@MainActor
protocol SavePanelConfiguring: FilePanelConfiguring {
    var nameFieldLabel: String! { get set }
    var nameFieldStringValue: String { get set }
    var canCreateDirectories: Bool { get set }
    var showsTagField: Bool { get set }
    var url: URL? { get }
}

extension NSOpenPanel: OpenPanelConfiguring {}
extension NSSavePanel: SavePanelConfiguring {}

@MainActor
struct SystemFilePanels: FilePanelPresenting {
    var makeOpenPanel: @MainActor () -> any OpenPanelConfiguring = NSOpenPanel.init
    var makeSavePanel: @MainActor () -> any SavePanelConfiguring = NSSavePanel.init
    var isHeadless: @MainActor () -> Bool = { DreamderHeadless.isEnabled }

    func chooseFiles(_ request: OpenPanelRequest) -> [URL] {
        guard !isHeadless() else {
            DreamderHeadless.recordSuppressedModal(request.summary)
            return []
        }
        return run(request, on: makeOpenPanel())
    }

    func chooseSaveLocation(_ request: SavePanelRequest) -> URL? {
        guard !isHeadless() else {
            DreamderHeadless.recordSuppressedModal(request.summary)
            return nil
        }
        return run(request, on: makeSavePanel())
    }

    func run(_ request: OpenPanelRequest, on panel: some OpenPanelConfiguring) -> [URL] {
        panel.allowedContentTypes = request.allowedContentTypes
        panel.canChooseFiles = request.canChooseFiles
        panel.canChooseDirectories = request.canChooseDirectories
        panel.allowsMultipleSelection = request.allowsMultipleSelection
        panel.showsHiddenFiles = request.showsHiddenFiles
        if let title = request.title { panel.title = title }
        if let prompt = request.prompt { panel.prompt = prompt }
        if let message = request.message { panel.message = message }
        return panel.runModal() == .OK ? panel.urls : []
    }

    func run(_ request: SavePanelRequest, on panel: some SavePanelConfiguring) -> URL? {
        panel.nameFieldStringValue = request.nameFieldStringValue
        panel.allowedContentTypes = request.allowedContentTypes
        panel.canCreateDirectories = request.canCreateDirectories
        panel.showsHiddenFiles = request.showsHiddenFiles
        panel.showsTagField = request.showsTagField
        if let title = request.title { panel.title = title }
        if let prompt = request.prompt { panel.prompt = prompt }
        if let message = request.message { panel.message = message }
        if let label = request.nameFieldLabel { panel.nameFieldLabel = label }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
