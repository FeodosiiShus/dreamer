import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
enum CEWorkspaceSettingsCoverageFixture {
    static func host<Content: View>(
        _ workspace: WorkspaceDocument,
        size: NSSize = NSSize(width: 520, height: 520),
        @ViewBuilder _ content: () -> Content
    ) throws -> HostedView {
        let settings = try #require(workspace.workspaceSettingsManager)
        let view = content()
        return try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            view.environment(settings)
        }
    }

    static func menu<Content: View>(@ViewBuilder _ content: () -> Content) -> NSMenu {
        let menu = NSHostingMenu(rootView: content())
        menu.update()
        return menu
    }

    static func endSheets(of hosted: HostedView) {
        while let sheet = hosted.window.attachedSheet {
            hosted.window.endSheet(sheet)
        }
    }
}

@Observable
@MainActor
final class CEWorkspaceSettingsCoverageSelection {
    var taskID: UUID?
    var showsSheet = false
}
