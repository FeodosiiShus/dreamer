import AppKit
import CodeEditSourceEditor
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StatusBarCoverageTests {
    func writeFile(in directory: URL, _ relative: String, contents: String = "let value = 1\n") throws -> URL {
        let url = directory.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writePNG(in directory: URL, _ name: String, width: Int, height: Int) throws -> URL {
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try #require(representation.representation(using: .png, properties: [:]))
        let url = directory.appending(path: name)
        try data.write(to: url)
        return url
    }

    func open(_ url: URL, in workspace: WorkspaceDocument) throws {
        let path = url.path(percentEncoded: false)
        let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
        try #require(workspace.editorManager).openTab(item: file)
    }

    private func fileSize(_ url: URL) throws -> Int {
        try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    @Test
    func everyFileEncodingHasAStatusBarLabel() {
        #expect(FileEncoding.utf8.statusBarLabel == "UTF-8")
        #expect(FileEncoding.utf16BE.statusBarLabel == "UTF-16 BE")
        #expect(FileEncoding.utf16LE.statusBarLabel == "UTF-16 LE")
        #expect(FileEncoding.allCases.count == 3)
    }

    @Test
    func cursorLabelDescribesEverySelectionShape() {
        let label = StatusBarCursorPositionLabel.LineLabel.label
        let noLines: (NSRange) -> Int = { _ in 0 }
        let threeLines: (NSRange) -> Int = { _ in 3 }

        #expect(label([], [], noLines) == "")
        let two = [CursorPosition(line: 1, column: 1), CursorPosition(line: 2, column: 1)]
        #expect(label(two, [], noLines) == "2 selections")
        #expect(label([CursorPosition(range: NSRange(location: 3, length: 5))], [.option], noLines) == "Char: 3 Len: 5")
        #expect(label([CursorPosition(range: NSRange(location: 3, length: 5))], [], threeLines) == "3 lines")
        #expect(label([CursorPosition(range: NSRange(location: 3, length: 5))], [], noLines) == "5 characters")
        #expect(label([CursorPosition(range: NSRange(location: 4, length: 0))], [.option], noLines) == "Char: 4 Len: 0")
        #expect(label([CursorPosition(range: NSRange(location: 4, length: 0))], [], noLines) == "")
        #expect(label([CursorPosition(line: 4, column: 0)], [], noLines) == "")
        #expect(label([CursorPosition(line: 0, column: 2)], [], noLines) == "")
        #expect(label([CursorPosition(line: 4, column: 2)], [], noLines) == "4:2")
    }

    @Test
    func cursorLabelRendersWithAndWithoutAnActiveTab() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let empty = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 120, height: 30)) {
                StatusBarCursorPositionLabel()
            }
            defer { empty.close() }
            try await empty.settle()

            let url = try writeFile(in: dir, "One.swift")
            try open(url, in: workspace)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            let withTab = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 120, height: 30)) {
                StatusBarCursorPositionLabel()
            }
            let option = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 120, height: 30)) {
                StatusBarCursorPositionLabel.LineLabel(editorInstance: tab).environment(\.modifierKeys, [.option])
            }
            defer {
                withTab.close()
                option.close()
            }
            try await withTab.settle()
            try await option.settle()

            #expect(withTab.renders())
            #expect(option.renders())
            let lineLabel = StatusBarCursorPositionLabel.LineLabel(editorInstance: tab)
            #expect(lineLabel.getLines(NSRange(location: 0, length: 4)) == 0)
        }
    }

    @Test
    func statusBarInfoReadsTheSizeOfATextFileWhenTheViewAppears() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            let url = try writeFile(in: dir, "Text.swift", contents: "let a = 1\nlet b = 2\n")
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: url))
            }
            defer { hosted.close() }

            let expected = try fileSize(url)
            try await eventually { viewModel.fileSize == expected }

            #expect(viewModel.dimensions == nil)
        }
    }

    @Test
    func statusBarInfoReadsImageDimensions() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            let url = try writePNG(in: dir, "Image.png", width: 2, height: 3)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: url))
            }
            defer { hosted.close() }

            let expected = try fileSize(url)
            try await eventually { viewModel.fileSize == expected }

            #expect(viewModel.dimensions?.width == 2)
            #expect(viewModel.dimensions?.height == 3)
        }
    }

    @Test
    func statusBarInfoFallsBackToNoDimensionsForUnreadableImages() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            let url = try writeFile(in: dir, "Broken.png", contents: "not an image")
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: url))
            }
            defer { hosted.close() }

            let expected = try fileSize(url)
            try await eventually { viewModel.fileSize == expected }

            #expect(viewModel.dimensions == nil)
        }
    }

    @Test
    func statusBarInfoClearsValuesForMissingFiles() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            viewModel.fileSize = 42
            viewModel.dimensions = ImageDimensions(width: 1, height: 1)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: dir.appending(path: "Missing.swift")))
            }
            defer { hosted.close() }

            try await eventually { viewModel.fileSize == nil }

            #expect(viewModel.dimensions == nil)
        }
    }

    @Test
    func statusBarInfoLeavesTheViewModelAloneWithoutAFileURL() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            viewModel.fileSize = 42
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: nil))
            }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(viewModel.fileSize == 42)
        }
    }

    @Test
    func statusBarInfoFollowsTheSelectedTab() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let viewModel = try #require(workspace.statusBarViewModel)
            let first = try writeFile(in: dir, "First.swift", contents: "1\n")
            let second = try writeFile(in: dir, "Second.swift", contents: "22222222\n")
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                Color.clear.modifier(UpdateStatusBarInfo(with: first))
            }
            defer { hosted.close() }
            let firstSize = try fileSize(first)
            try await eventually { viewModel.fileSize == firstSize }

            try open(second, in: workspace)
            let secondSize = try fileSize(second)
            try await eventually { viewModel.fileSize == secondSize }

            let editor = try #require(workspace.editorManager?.activeEditor)
            let secondFile = try #require(editor.selectedTab?.file)
            editor.closeTab(file: secondFile)
            try await hosted.settle()

            #expect(editor.selectedTab == nil)
            #expect(viewModel.fileSize == secondSize)
        }
    }
}
