import AppKit
import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewLinkPolicyTests {
    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test(arguments: [
        "https://example.com/a?b=c#d", "http://example.com", "mailto:someone@example.com", "HTTPS://EXAMPLE.COM/UP"
    ])
    func webAndMailLinksOpenExternally(text: String) throws {
        let link = try url(text)

        #expect(MarkdownPreviewLinkPolicy.action(for: link, workspaceRoot: nil) == .openExternally(link))
    }

    @Test(arguments: [
        "javascript:alert(1)", "vbscript:msgbox(1)", "data:text/html,hello", "ftp://example.com/file",
        "ssh://example.com", "smb://server/share", "tel:+123456", "x-apple.systempreferences:com.apple.preference",
        "dreamder-unhandled://nothing", "payload.command", "../payload.command", "#anchor"
    ])
    func everyOtherSchemeAndSchemelessLinkIsRefused(text: String) throws {
        let link = try url(text)

        #expect(MarkdownPreviewLinkPolicy.action(for: link, workspaceRoot: URL(fileURLWithPath: "/")) == .refuse)
    }

    @Test
    func fileLinksInsideTheWorkspaceOpenInTheEditor() throws {
        try withTempDir { directory in
            let target = directory.appending(path: "docs/a.md").standardizedFileURL
            let plain = target
            let withFragment = try url(target.absoluteString + "#intro")
            let withQuery = try url(target.absoluteString + "?x=1#line")
            let traversal = URL(fileURLWithPath: directory.path + "/docs/../docs/a.md")
            let localhost = try url("file://localhost" + target.path)

            for link in [plain, withFragment, withQuery, traversal, localhost] {
                #expect(MarkdownPreviewLinkPolicy.action(for: link, workspaceRoot: directory) == .openInEditor(target))
            }
        }
    }

    @Test
    func theWorkspaceRootMayBeGivenThroughASymlinkedSpelling() throws {
        try withTempDir { directory in
            let resolvedRoot = directory.resolvingSymlinksInPath()
            let target = directory.appending(path: "a.md").standardizedFileURL

            #expect(MarkdownPreviewLinkPolicy.action(for: target, workspaceRoot: resolvedRoot) == .openInEditor(target))
        }
    }

    @Test
    func aWorkspaceRootOfSlashContainsEveryAbsolutePath() throws {
        let hosts = URL(fileURLWithPath: "/etc/hosts")

        #expect(
            MarkdownPreviewLinkPolicy.action(for: hosts, workspaceRoot: URL(fileURLWithPath: "/"))
                == .openInEditor(hosts)
        )
    }

    @Test
    func fileLinksOutsideTheWorkspaceAreRefused() throws {
        try withTempDir { directory in
            let sibling = try url("file://" + directory.path + "-sibling/payload.command")
            let escaping = URL(fileURLWithPath: directory.path + "/../payload.command")
            let elsewhere = URL(fileURLWithPath: "/usr/bin/true")
            let remote = try url("file://evil.example" + directory.path + "/a.md")
            let inside = directory.appending(path: "a.md")

            for link in [sibling, escaping, elsewhere, remote, directory] {
                #expect(MarkdownPreviewLinkPolicy.action(for: link, workspaceRoot: directory) == .refuse)
            }
            #expect(MarkdownPreviewLinkPolicy.action(for: inside, workspaceRoot: nil) == .refuse)
        }
    }

    @Test
    func aSymlinkInsideTheWorkspacePointingOutsideIsRefused() throws {
        try withTempDir { directory in
            let workspace = directory.appending(path: "workspace")
            let outside = directory.appending(path: "outside")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try "x".write(to: outside.appending(path: "payload.command"), atomically: true, encoding: .utf8)
            let link = workspace.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

            let target = link.appending(path: "payload.command")

            #expect(MarkdownPreviewLinkPolicy.action(for: target, workspaceRoot: workspace) == .refuse)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct MarkdownPreviewLinksTests {
    @MainActor
    private final class Recorder {
        var external: [URL] = []
        var editor: [URL] = []
    }

    private func makeLinks(root: URL?, recorder: Recorder) -> MarkdownPreviewLinks {
        MarkdownPreviewLinks(
            workspaceRoot: root,
            openExternal: { recorder.external.append($0) },
            openInEditor: { recorder.editor.append($0) }
        )
    }

    @Test
    func handleRoutesEachActionToItsOpener() throws {
        try withTempDir { directory in
            let recorder = Recorder()
            let links = makeLinks(root: directory, recorder: recorder)
            let web = try #require(URL(string: "https://example.com"))
            let file = directory.appending(path: "a.md").standardizedFileURL
            let script = try #require(URL(string: "javascript:alert(1)"))

            links.handle(web)
            links.handle(file)
            links.handle(script)

            #expect(recorder.external == [web])
            #expect(recorder.editor == [file])
        }
    }

    @Test
    func theLiveLinksUseTheWorkspaceFolderAndTheSystemOpener() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let unhandled = try #require(URL(string: "dreamder-coverage-unhandled-scheme://nothing"))

            let live = MarkdownPreviewLinks.live(workspace: workspace)
            live.openExternal(unhandled)

            #expect(live.workspaceRoot?.resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
            #expect(MarkdownPreviewLinks.live(workspace: nil).workspaceRoot == nil)
        }
    }

    @Test
    func theLiveEditorOpenerOpensWorkspaceFilesAsTabs() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "notes.md")
            try "# notes\n".write(to: file, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)

            MarkdownPreviewLinks.live(workspace: workspace).openInEditor(file)

            let tabs = editorManager.activeEditor.tabs.map { $0.file.url.resolvingSymlinksInPath().path }
            #expect(tabs == [file.resolvingSymlinksInPath().path])
        }
    }

    @Test
    func theEditorOpenerIgnoresMissingFilesDirectoriesAndWorkspacesWithoutEditors() throws {
        try withTempDir { directory in
            let folder = directory.appending(path: "folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = directory.appending(path: "notes.md")
            try "# notes\n".write(to: file, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)

            MarkdownPreviewLinks.openFile(directory.appending(path: "missing.md"), in: workspace)
            MarkdownPreviewLinks.openFile(folder, in: workspace)
            #expect(editorManager.activeEditor.tabs.isEmpty)

            workspace.editorManager = nil
            MarkdownPreviewLinks.openFile(file, in: workspace)
            #expect(editorManager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func theEditorOpenerFallsBackToAFreshWorkspaceFileWithoutAFileManager() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "notes.md")
            try "# notes\n".write(to: file, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editorManager = try #require(workspace.editorManager)
            workspace.workspaceFileManager = nil

            MarkdownPreviewLinks.openFile(file, in: workspace)

            let tabs = editorManager.activeEditor.tabs.map { $0.file.url.resolvingSymlinksInPath().path }
            #expect(tabs == [file.resolvingSymlinksInPath().path])
        }
    }

    @Test
    func theLiveEditorOpenerDoesNothingOnceTheWorkspaceIsGone() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "notes.md")
            try "# notes\n".write(to: file, atomically: true, encoding: .utf8)
            var workspace: WorkspaceDocument? = try HostedViewFixture.makeWorkspace(in: directory)
            let live = MarkdownPreviewLinks.live(workspace: workspace)
            workspace?.close()
            workspace = nil

            live.openInEditor(file)

            #expect(workspace == nil)
        }
    }
}
