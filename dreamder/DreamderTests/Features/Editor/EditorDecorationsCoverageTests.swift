import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorDecorationsCoverageTests {
    private static let errorGroup = "dreamder.diagnostics.error"
    private static let warningGroup = "dreamder.diagnostics.warning"
    private static let diagnosticsSource = "let alpha = 1\nlet beta = 2\nlet gamma = 3\n"
    private static let indentedSource =
        "func a() {\n    let x = 1\n    let y = 2\n\n    if x {\n        let z = 3\n    }\n}\n"

    private func diagnostic(
        _ severity: WorkspaceDiagnostic.Severity,
        file: URL,
        line: Int
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: file,
            startLine: line,
            startColumn: 0,
            endLine: line,
            endColumn: 3,
            severity: severity,
            message: "message \(line)",
            source: nil,
            code: nil
        )
    }

    private func ranges(of group: String, in session: DecorationsCoverageSession) -> [NSRange] {
        session.textView.emphasisManager?.getEmphases(for: group).map(\.range) ?? []
    }

    @Test
    func destroyingTheDiagnosticCoordinatorRemovesUnderlinesAndStopsFollowingTheStore() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(
                in: directory,
                contents: Self.diagnosticsSource,
                withWorkspace: true
            ) { fixture in
                [fixture.document.contentCoordinator, DiagnosticHighlightCoordinator(codeFile: fixture.document)]
            }
            defer { session.close() }
            let workspace = try #require(session.workspace)
            let coordinator = try #require(session.hosted.coordinator(ofType: DiagnosticHighlightCoordinator.self))
            workspace.diagnosticsStore.replace(
                [
                    diagnostic(.error, file: session.fileURL, line: 0),
                    diagnostic(.warning, file: session.fileURL, line: 1)
                ],
                for: session.fileURL
            )
            try await eventually {
                !ranges(of: Self.errorGroup, in: session).isEmpty && !ranges(of: Self.warningGroup, in: session).isEmpty
            }

            coordinator.destroy()

            #expect(ranges(of: Self.errorGroup, in: session).isEmpty)
            #expect(ranges(of: Self.warningGroup, in: session).isEmpty)
            workspace.diagnosticsStore.replace(
                [diagnostic(.error, file: session.fileURL, line: 2)],
                for: session.fileURL
            )
            coordinator.textViewDidChangeText(controller: session.controller)
            try await Task.sleep(for: .milliseconds(150))
            #expect(ranges(of: Self.errorGroup, in: session).isEmpty)
        }
    }

    @Test
    func themeBackgroundIsRestoredWhenNoBackgroundImageIsConfigured() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: "x\n") { fixture in
                [fixture.document.contentCoordinator, EditorBackgroundCoordinator(defaults: isolated.defaults)]
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: EditorBackgroundCoordinator.self))
            let scrollView = try #require(session.controller.scrollView)
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            scrollView.backgroundColor = .systemRed

            coordinator.controllerDidAppear(controller: session.controller)

            #expect(scrollView.drawsBackground)
            #expect(scrollView.contentView.drawsBackground)
            #expect(scrollView.backgroundColor == session.controller.theme.background)
        }
    }

    @Test
    func transparentThemeConfigurationKeepsTheScrollViewBackground() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: "x\n") { fixture in
                [fixture.document.contentCoordinator, EditorBackgroundCoordinator(defaults: isolated.defaults)]
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: EditorBackgroundCoordinator.self))
            let scrollView = try #require(session.controller.scrollView)
            session.controller.configuration.appearance.useThemeBackground = false
            scrollView.backgroundColor = .systemRed

            coordinator.controllerDidAppear(controller: session.controller)

            #expect(scrollView.drawsBackground)
            #expect(scrollView.backgroundColor == .systemRed)
        }
    }

    @Test
    func backgroundImageSettingTogglesEditorTransparencyThroughDefaultsNotifications() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: "x\n") { fixture in
                [fixture.document.contentCoordinator, EditorBackgroundCoordinator(defaults: isolated.defaults)]
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: EditorBackgroundCoordinator.self))
            let scrollView = try #require(session.controller.scrollView)
            coordinator.controllerDidAppear(controller: session.controller)
            coordinator.controllerDidAppear(controller: session.controller)
            #expect(scrollView.drawsBackground)

            isolated.defaults.set("/tmp/dreamder-background.png", forKey: Islands.BackgroundImageKey.path)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: isolated.defaults)
            try await eventually { !scrollView.drawsBackground && !scrollView.contentView.drawsBackground }
            #expect(scrollView.contentView.backgroundColor == .clear)

            isolated.defaults.removeObject(forKey: Islands.BackgroundImageKey.path)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: isolated.defaults)
            try await eventually { scrollView.drawsBackground && scrollView.contentView.drawsBackground }
        }
    }

    @Test
    func disappearingAndDestroyingStopObservingDefaultsChanges() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: "x\n") { fixture in
                [fixture.document.contentCoordinator, EditorBackgroundCoordinator(defaults: isolated.defaults)]
            }
            defer { session.close() }
            try await Task.sleep(for: .milliseconds(200))
            let coordinator = try #require(session.hosted.coordinator(ofType: EditorBackgroundCoordinator.self))
            let scrollView = try #require(session.controller.scrollView)
            coordinator.controllerDidAppear(controller: session.controller)

            coordinator.controllerDidDisappear(controller: session.controller)
            isolated.defaults.set("/tmp/dreamder-background.png", forKey: Islands.BackgroundImageKey.path)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: isolated.defaults)
            try await Task.sleep(for: .milliseconds(150))
            #expect(scrollView.drawsBackground)

            coordinator.controllerDidAppear(controller: session.controller)
            #expect(!scrollView.drawsBackground)
            coordinator.destroy()
            isolated.defaults.removeObject(forKey: Islands.BackgroundImageKey.path)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: isolated.defaults)
            try await Task.sleep(for: .milliseconds(150))
            #expect(!scrollView.drawsBackground)

            coordinator.controllerDidAppear(controller: session.controller)
            #expect(!scrollView.drawsBackground)
            coordinator.destroy()
        }
    }

    private func indentSession(
        in directory: URL,
        contents: String = EditorDecorationsCoverageTests.indentedSource
    ) async throws -> DecorationsCoverageSession {
        let session = try await DecorationsCoverageHost.open(in: directory, contents: contents) { fixture in
            [fixture.document.contentCoordinator, IndentGuideCoordinator()]
        }
        try await eventually { !session.hosted.views(ofType: IndentGuideOverlayView.self).isEmpty }
        return session
    }

    private func guideColor(
        in representation: NSBitmapImageRep,
        overlay: IndentGuideOverlayView,
        depth: Int,
        lineIndex: Int,
        area: NSRect
    ) throws -> NSColor? {
        let textView = try #require(overlay.textView)
        let line = try #require(textView.layoutManager.textLineForIndex(lineIndex))
        let charWidth = (" " as NSString).size(withAttributes: [.font: textView.font]).width
        let inset = textView.layoutManager.edgeInsets.left
        let x = (inset + CGFloat(depth * overlay.tabWidth) * charWidth).rounded() - 0.5
        return DecorationsCoveragePixels.color(
            in: representation,
            at: NSPoint(x: x, y: line.yPos + line.height / 2),
            area: area
        )
    }

    private func moveCaret(to lineIndex: Int, in session: DecorationsCoverageSession) throws {
        let location = try session.lineStart(lineIndex) + 4
        session.textView.selectionManager.setSelectedRange(NSRange(location: location, length: 0))
        let coordinator = try #require(session.hosted.coordinator(ofType: IndentGuideCoordinator.self))
        coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
    }

    @Test
    func caretBlockGuideIsDrawnBrighterThanTheOtherGuides() async throws {
        try await withTempDir { directory in
            let session = try await indentSession(in: directory)
            defer { session.close() }
            let overlay = try #require(session.hosted.views(ofType: IndentGuideOverlayView.self).first)
            overlay.matchSuperviewBounds()
            let area = overlay.bounds

            try moveCaret(to: 5, in: session)
            let deepCaret = try DecorationsCoveragePixels.render(overlay)
            let deepInactive = try #require(
                try guideColor(in: deepCaret, overlay: overlay, depth: 1, lineIndex: 5, area: area)
            )
            let deepActive = try #require(
                try guideColor(in: deepCaret, overlay: overlay, depth: 2, lineIndex: 5, area: area)
            )
            #expect(deepInactive.alphaComponent > 0.9)
            #expect(deepActive.alphaComponent > 0.9)
            #expect(deepActive.redComponent > deepInactive.redComponent + 0.05)
            let outsideBlock = try #require(
                try guideColor(in: deepCaret, overlay: overlay, depth: 1, lineIndex: 2, area: area)
            )
            #expect(outsideBlock.redComponent < deepActive.redComponent - 0.05)

            try moveCaret(to: 2, in: session)
            let shallowCaret = try DecorationsCoveragePixels.render(overlay)
            let shallowFirst = try #require(
                try guideColor(in: shallowCaret, overlay: overlay, depth: 1, lineIndex: 2, area: area)
            )
            let shallowNested = try #require(
                try guideColor(in: shallowCaret, overlay: overlay, depth: 1, lineIndex: 5, area: area)
            )
            let shallowDeepGuide = try #require(
                try guideColor(in: shallowCaret, overlay: overlay, depth: 2, lineIndex: 5, area: area)
            )
            #expect(shallowFirst.redComponent > shallowDeepGuide.redComponent + 0.05)
            #expect(shallowNested.redComponent > shallowDeepGuide.redComponent + 0.05)
            let unindented = try #require(
                try guideColor(in: shallowCaret, overlay: overlay, depth: 1, lineIndex: 0, area: area)
            )
            #expect(unindented.alphaComponent == 0)
        }
    }

    @Test
    func caretOnAnUnindentedLineHighlightsNoGuide() async throws {
        try await withTempDir { directory in
            let session = try await indentSession(in: directory)
            defer { session.close() }
            let overlay = try #require(session.hosted.views(ofType: IndentGuideOverlayView.self).first)
            overlay.matchSuperviewBounds()
            let area = overlay.bounds

            try moveCaret(to: 0, in: session)
            let representation = try DecorationsCoveragePixels.render(overlay)
            let first = try #require(try guideColor(in: representation, overlay: overlay, depth: 1, lineIndex: 2, area: area))
            let nested = try #require(try guideColor(in: representation, overlay: overlay, depth: 2, lineIndex: 5, area: area))

            #expect(first.alphaComponent > 0.9)
            #expect(abs(first.redComponent - nested.redComponent) < 0.02)
        }
    }

    @Test
    func blankRunsLongerThanTheInheritLimitDoNotInheritTheIndentation() async throws {
        try await withTempDir { directory in
            let contents = "    a\n" + String(repeating: "\n", count: 260) + "    b\n"
            let session = try await indentSession(in: directory, contents: contents)
            defer { session.close() }
            let overlay = try #require(session.hosted.views(ofType: IndentGuideOverlayView.self).first)
            overlay.matchSuperviewBounds()

            try moveCaret(to: 240, in: session)
            let topArea = NSRect(x: 0, y: 0, width: min(300, overlay.bounds.width), height: 120)
            let representation = try DecorationsCoveragePixels.render(overlay, in: topArea)
            let firstLine = try #require(
                try guideColor(in: representation, overlay: overlay, depth: 1, lineIndex: 0, area: topArea)
            )
            let blankNearTop = try #require(
                try guideColor(in: representation, overlay: overlay, depth: 1, lineIndex: 2, area: topArea)
            )

            #expect(firstLine.alphaComponent > 0.9)
            #expect(blankNearTop.alphaComponent > 0.9)
        }
    }

    @Test
    func coordinatorRefreshesTheOverlayOnTextAndSelectionChangesAndRemovesItOnDestroy() async throws {
        try await withTempDir { directory in
            let session = try await indentSession(in: directory)
            defer { session.close() }
            let overlay = try #require(session.hosted.views(ofType: IndentGuideOverlayView.self).first)
            let coordinator = try #require(session.hosted.coordinator(ofType: IndentGuideCoordinator.self))
            #expect(overlay.superview === session.textView)
            #expect(overlay.tabWidth == session.controller.tabWidth)

            session.controller.configuration.appearance.tabWidth = 2
            coordinator.textViewDidChangeText(controller: session.controller)
            #expect(overlay.tabWidth == 2)
            let afterText = try DecorationsCoveragePixels.render(overlay)
            let twoColumnGuide = try #require(
                try guideColor(in: afterText, overlay: overlay, depth: 1, lineIndex: 1, area: overlay.bounds)
            )
            #expect(twoColumnGuide.alphaComponent > 0.9)

            session.controller.configuration.appearance.tabWidth = 3
            coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            #expect(overlay.tabWidth == 3)
            let afterSelection = try DecorationsCoveragePixels.render(overlay)
            let threeColumnGuide = try #require(
                try guideColor(in: afterSelection, overlay: overlay, depth: 1, lineIndex: 1, area: overlay.bounds)
            )
            #expect(threeColumnGuide.alphaComponent > 0.9)

            coordinator.destroy()
            #expect(overlay.superview == nil)
            #expect(session.hosted.views(ofType: IndentGuideOverlayView.self).isEmpty)
            coordinator.textViewDidChangeText(controller: session.controller)
            #expect(session.hosted.views(ofType: IndentGuideOverlayView.self).isEmpty)
        }
    }

    @Test
    func overlayIgnoresHitsAndCannotBeDecoded() {
        let overlay = IndentGuideOverlayView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        #expect(overlay.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(IndentGuideOverlayView(coder: NSCoder()) == nil)
    }

    @Test
    func overlayWithoutATextViewOrWithZeroTabWidthDrawsNothing() throws {
        let overlay = IndentGuideOverlayView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        overlay.matchSuperviewBounds()

        let empty = try DecorationsCoveragePixels.render(overlay)
        let sample = DecorationsCoveragePixels.color(in: empty, at: NSPoint(x: 10, y: 10), area: overlay.bounds)
        overlay.tabWidth = 0
        overlay.draw(overlay.bounds)

        #expect(sample?.alphaComponent == 0)
    }

    @Test
    func nonPositiveTabWidthYieldsNoIndentation() {
        #expect(IndentGuides.indentationColumns(of: "    let a = 1", tabWidth: 0) == 0)
        #expect(IndentGuides.indentationColumns(of: "\tlet a = 1", tabWidth: -4) == 0)
        #expect(IndentGuides.levels(of: ["    a", "\tb", ""], tabWidth: 0) == [0, 0, 0])
        #expect(IndentGuides.levels(of: ["    a"], tabWidth: -1) == [0])
    }

    @Test
    func blocksExtendUpwardThroughEqualOrDeeperLines() {
        #expect(IndentGuides.block(containingLine: 2, levels: [1, 1, 1]) == 0...2)
        #expect(IndentGuides.block(containingLine: 3, levels: [0, 1, 2, 2]) == 2...3)
        #expect(IndentGuides.block(containingLine: 2, levels: [2, 1, 2]) == 2...2)
    }
}
