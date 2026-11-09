import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

func renameKeyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    ))
}

@MainActor
final class RenameNameResults {
    var values: [String?] = []

    func append(_ value: String?) {
        values.append(value)
    }

    func present(_ model: RenamePopupViewModel, in harness: RenameWindowHarness) async throws {
        Task { @MainActor in
            append(await RenamePanelHost.shared.present(model, anchor: nil, in: harness.controller))
        }
        try await eventually { harness.renameModel === model }
    }
}

@MainActor
struct RenameWindowHarness {
    let workspace: WorkspaceDocument
    let controller: DreamderWindowController
    let window: NSWindow

    static func make(in directory: URL) throws -> RenameWindowHarness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return RenameWindowHarness(workspace: workspace, controller: controller, window: window)
    }

    var panels: [ShowUsagesPanel] {
        window.childWindows?.compactMap { $0 as? ShowUsagesPanel } ?? []
    }

    var renamePanels: [ShowUsagesPanel] {
        panels.filter { $0.contentView is NSHostingView<RenamePopupView> }
    }

    var messagePanels: [ShowUsagesPanel] {
        panels.filter { $0.contentView is NSHostingView<ShowUsagesView> }
    }

    var renameModel: RenamePopupViewModel? {
        (renamePanels.first?.contentView as? NSHostingView<RenamePopupView>)?.rootView.model
    }

    func close() {
        for child in window.childWindows ?? [] {
            child.close()
        }
        window.close()
        workspace.close()
    }
}
