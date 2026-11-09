import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StatusBarIndentSelectorTests {
    private typealias IndentOption = SettingsData.TextEditingSettings.IndentOption

    private func makeDocument(in directory: URL, editorConfig: String, text: String) throws -> CodeFileDocument {
        try "root = true\n\(editorConfig)".write(
            to: directory.appending(path: ".editorconfig"),
            atomically: true,
            encoding: .utf8
        )
        let url = directory.appending(path: "file.txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
    }

    @Test
    func labelsDescribeTheResolvedIndent() {
        let tabs = ResolvedIndent(style: .tab, spaceCount: 4, tabWidth: 8, styleSource: .global)
        let spaces = ResolvedIndent(style: .spaces, spaceCount: 2, tabWidth: 8, styleSource: .detected)

        #expect(StatusBarIndentSelector.label(for: tabs) == "Tabs (8)")
        #expect(StatusBarIndentSelector.label(for: spaces) == "2 spaces")
    }

    @Test
    func theSelectorShowsTheEffectiveValueOfTheDocument() throws {
        try withTempDir { dir in
            let document = try makeDocument(
                in: dir,
                editorConfig: "[*.txt]\nindent_style = tab\ntab_width = 3\n",
                text: "a\n"
            )
            let selector = StatusBarIndentSelector(document: document)

            #expect(selector.resolved == document.resolvedIndent)
            #expect(selector.label == "Tabs (3)")
        }
    }

    @Test
    func withoutADocumentTheSelectorShowsTheGlobalSetting() {
        let selector = StatusBarIndentSelector()
        let editing = Dreamder.Settings[\.textEditing]

        #expect(selector.resolved == StatusBarIndentSelector.globalResolved())
        #expect(selector.resolved.styleSource == .global)
        #expect(selector.resolved.spaceCount == editing.indentOption.spaceCount)
        #expect(selector.resolved.tabWidth == editing.defaultTabWidth)
        #expect(selector.label == StatusBarIndentSelector.label(for: StatusBarIndentSelector.globalResolved()))
    }

    @Test
    func choosingTabsWritesAPerDocumentOverrideAndLeavesTheGlobalSettingAlone() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, editorConfig: "[*.txt]\nindent_size = 2\n", text: "a\n")
            let globalBefore = Dreamder.Settings[\.textEditing].indentOption
            let selector = StatusBarIndentSelector(document: document)

            selector.useTabs()

            #expect(document.indentOption == IndentOption(indentType: .tab, spaceCount: 2))
            #expect(document.resolvedIndent.style == .tab)
            #expect(document.resolvedIndent.styleSource == .documentOverride)
            #expect(StatusBarIndentSelector(document: document).label.hasPrefix("Tabs"))
            #expect(Dreamder.Settings[\.textEditing].indentOption == globalBefore)
        }
    }

    @Test
    func choosingSpacesKeepsTheEffectiveIndentSize() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, editorConfig: "[*.txt]\nindent_style = tab\n", text: "a\n")
            let expectedCount = document.resolvedIndent.spaceCount
            let selector = StatusBarIndentSelector(document: document)

            selector.useSpaces()

            #expect(document.indentOption == IndentOption(indentType: .spaces, spaceCount: expectedCount))
            #expect(document.resolvedIndent.style == .spaces)
            #expect(StatusBarIndentSelector(document: document).label == "\(expectedCount) spaces")
        }
    }

    @Test
    func changingTheIndentSizeKeepsTheCurrentStyle() throws {
        try withTempDir { dir in
            let tabDocument = try makeDocument(in: dir, editorConfig: "[*.txt]\nindent_style = tab\n", text: "a\n")
            StatusBarIndentSelector(document: tabDocument).setIndentSize(6)
            #expect(tabDocument.indentOption == IndentOption(indentType: .tab, spaceCount: 6))

            let spaceDocument = try makeDocument(in: dir, editorConfig: "[*.txt]\nindent_style = space\n", text: "a\n")
            StatusBarIndentSelector(document: spaceDocument).setIndentSize(3)
            #expect(spaceDocument.indentOption == IndentOption(indentType: .spaces, spaceCount: 3))
            #expect(spaceDocument.resolvedIndent.spaceCount == 3)
        }
    }

    @Test
    func changingTheTabWidthWritesTheDocumentOverride() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, editorConfig: "", text: "a\n")
            let globalWidth = Dreamder.Settings[\.textEditing].defaultTabWidth

            StatusBarIndentSelector(document: document).setTabWidth(7)

            #expect(document.defaultTabWidth == 7)
            #expect(document.resolvedIndent.tabWidth == 7)
            #expect(Dreamder.Settings[\.textEditing].defaultTabWidth == globalWidth)
        }
    }

    @Test
    func withoutADocumentTheActionsDoNothing() {
        let selector = StatusBarIndentSelector()
        let optionBefore = Dreamder.Settings[\.textEditing].indentOption
        let widthBefore = Dreamder.Settings[\.textEditing].defaultTabWidth

        selector.useTabs()
        selector.useSpaces()
        selector.setIndentSize(2)
        selector.setTabWidth(8)

        #expect(Dreamder.Settings[\.textEditing].indentOption == optionBefore)
        #expect(Dreamder.Settings[\.textEditing].defaultTabWidth == widthBefore)
    }

    @Test
    func menuChoicesCoverTheSupportedSizes() {
        #expect(StatusBarIndentSelector.indentSizes == Array(1...8))
        #expect(StatusBarIndentSelector.tabWidths == Array(2...8))
    }

    @Test
    func pickerBindingsReadTheResolvedIndentAndWriteTheDocumentOverride() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, editorConfig: "[*.txt]\nindent_style = space\n", text: "a\n")
            let selector = StatusBarIndentSelector(document: document)

            #expect(selector.indentSizeBinding.wrappedValue == document.resolvedIndent.spaceCount)
            #expect(selector.tabWidthBinding.wrappedValue == document.resolvedIndent.tabWidth)

            selector.indentSizeBinding.wrappedValue = 5
            selector.tabWidthBinding.wrappedValue = 6

            #expect(document.indentOption == IndentOption(indentType: .spaces, spaceCount: 5))
            #expect(document.defaultTabWidth == 6)
        }
    }

    @Test
    func spacesOptionsRenderTheirCountAndHoverStateIsSettable() async throws {
        let selector = StatusBarIndentSelector()
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 40)) {
            selector.spacesOption(3)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        #expect(hosted.renders())
        selector.setHovering(true)
        selector.setHovering(false)
    }

    @Test
    func theSelectorRendersWithAndWithoutADocument() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir, editorConfig: "", text: "a\n")
            let withDocument = HostedViewFixture.host(size: NSSize(width: 200, height: 40)) {
                StatusBarIndentSelector(document: document)
            }
            defer { withDocument.close() }
            let withoutDocument = HostedViewFixture.host(size: NSSize(width: 200, height: 40)) {
                StatusBarIndentSelector()
            }
            defer { withoutDocument.close() }

            try await withDocument.settle()
            try await withoutDocument.settle()

            #expect(withDocument.renders())
            #expect(withoutDocument.renders())
        }
    }
}
