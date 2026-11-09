import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
struct ScmViewsCHarness {
    let root: URL
    let fixture: GitMergeFixture
    let workspace: WorkspaceDocument
    let manager: SourceControlManager

    static func make(in directory: URL, withRemote: Bool = false) async throws -> ScmViewsCHarness {
        let root = directory.appending(path: "work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("a.txt", "base\n")
        try await fixture.commit("base")
        try await fixture.run("branch", "feature")
        if withRemote {
            let origin = directory.appending(path: "origin.git", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
            try await GitMergeFixture(existing: origin).run("init", "--bare", "-q", "-b", "main")
            try await fixture.run("remote", "add", "origin", origin.path(percentEncoded: false))
            try await fixture.run("push", "-q", "-u", "origin", "main")
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: root)
        let manager = try #require(workspace.sourceControlManager)
        let harness = ScmViewsCHarness(root: root, fixture: fixture, workspace: workspace, manager: manager)
        await harness.refresh()
        return harness
    }

    func refresh() async {
        await manager.refreshBranches()
        await manager.refreshCurrentBranch()
        try? await manager.refreshStashEntries()
        await manager.refreshAllChangedFiles()
    }

    func dirtyWorkingTree() async throws {
        try fixture.write("a.txt", "changed\n")
        await manager.refreshAllChangedFiles()
    }

    func localBranch(named name: String) throws -> GitBranch {
        try #require(manager.branches.first { $0.name == name && $0.isLocal })
    }

    func host<Content: View>(
        _ view: Content,
        size: NSSize = NSSize(width: 560, height: 420)
    ) throws -> HostedView {
        let manager = manager
        return try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            view.environment(manager)
        }
    }

    func close() {
        workspace.close()
    }
}

@MainActor
enum ScmViewsCControls {
    static func switches(in hosted: HostedView) -> [NSSwitch] {
        hosted.views(of: NSSwitch.self)
            .sorted { $0.convert($0.bounds, to: nil).midY > $1.convert($1.bounds, to: nil).midY }
    }

    static func switchStates(in hosted: HostedView) -> [NSControl.StateValue] {
        switches(in: hosted).map(\.state)
    }

    @discardableResult
    static func type(_ text: String, in hosted: HostedView) throws -> NSTextView {
        if let textView = hosted.views(of: NSTextView.self).first(where: { $0.isEditable && !$0.isFieldEditor }) {
            hosted.window.makeFirstResponder(textView)
            textView.insertText(text, replacementRange: textView.selectedRange())
            return textView
        }
        let field = try #require(hosted.views(of: NSTextField.self).first { $0.isEditable })
        hosted.window.makeFirstResponder(field)
        if field.currentEditor() == nil {
            field.selectText(nil)
        }
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
        return editor
    }

    static func hasEditableField(in hosted: HostedView) -> Bool {
        hosted.views(of: NSTextField.self).contains { $0.isEditable }
            || hosted.views(of: NSTextView.self).contains { $0.isEditable && !$0.isFieldEditor }
    }
}
