import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class MergeRevisionsCoverageCloseCounter {
    var count = 0
}

@MainActor
private func mergeRevisionsCoverageModel(
    root: URL,
    path: String,
    load: Bool = true
) async throws -> MergeRevisionsViewModel {
    let document = WorkspaceDocument()
    document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
    let model = try #require(MergeRevisionsViewModel(workspace: document, path: path, autoLoad: false))
    if load {
        await model.load()
    }
    return model
}

@MainActor
private func mergeRevisionsCoverageTextView(in hosted: HostedView, pane: String) -> NSTextView? {
    hosted.views(of: NSTextView.self).first { $0.identifier?.rawValue == "merge-pane-\(pane)" }
}

@MainActor
private func mergeRevisionsCoverageHost(
    _ model: MergeRevisionsViewModel,
    counter: MergeRevisionsCoverageCloseCounter
) -> (view: MergeRevisionsView, hosted: HostedView) {
    let view = MergeRevisionsView(model: model) { counter.count += 1 }
    let hosted = HostedViewFixture.host(size: NSSize(width: 1240, height: 780)) { view }
    return (view, hosted)
}

@MainActor
private func mergeRevisionsCoverageAnswering<T>(_ answer: Bool, _ body: () -> T) -> T {
    MergeToolConfirmation.$override.withValue(answer) {
        body()
    }
}

@MainActor
@Suite(.uiGate)
struct MergeRevisionsViewCoverageTests {
    private let configPath = "app/config.txt"
    private let notesPath = "docs/notes.txt"
    private let resolvedLeftResult =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"
    private let resolvedRightResult =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-feature\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"

    private func conflictID(_ model: MergeRevisionsViewModel) throws -> Int {
        let merge = try #require(model.merge)
        return try #require(merge.blocks.first { $0.kind == .conflict }).id
    }

    private func paneText(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    private func click(_ action: String, block: Int, in hosted: HostedView, pane: String) throws {
        let textView = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: pane))
        let target = try #require(NSURL(string: "merge-block://\(action)/\(block)"))
        textView.clicked(onLink: target, at: 0)
    }

    @Test
    func loadingShowsTheProgressIndicatorUntilTheMergeArrives() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath, load: false)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.isLoading)
            #expect(model.summary == "Computing differences…")
            #expect(model.canApply == false)
            #expect(model.canApplyNonConflicting(.all) == false)
            #expect(hosted.views(of: NSTextView.self).isEmpty)
            #expect(hosted.renders())
            let loadingSnapshot = hosted.snapshot()

            await model.load()
            try await eventually {
                hosted.layout()
                return hosted.views(of: NSTextView.self).count == 3
            }
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(loadingSnapshot, hosted.snapshot()))
            #expect(counter.count == 0)
        }
    }

    @Test
    func conflictedMergeRendersThreePanesWithChipsInTheSideGutters() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }
            try await hosted.settle()

            let left = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "left"))
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result"))
            let right = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "right"))
            #expect(left.isEditable == false)
            #expect(result.isEditable)
            #expect(right.isEditable == false)
            #expect(left.string.contains("\u{00BB}"))
            #expect(left.string.contains("\u{00D7}"))
            #expect(left.string.contains("beta-main"))
            #expect(right.string.contains("\u{00AB}"))
            #expect(right.string.contains("zeta-feature"))
            #expect(result.string == model.resultPane.text)
            #expect(result.string.contains("\u{00BB}") == false)
            #expect(model.leftTitle == "Your version, branch main")
            #expect(model.rightTitle == "Theirs, branch feature")
            #expect(model.summary == "2 changes, 1 conflict")
            #expect(model.canApply)
            #expect(model.canAcceptSide)
            #expect(model.canApplyNonConflicting(.left))
            #expect(model.canApplyNonConflicting(.all))
            #expect(model.canApplyNonConflicting(.right))
            #expect(hosted.renders())
        }
    }

    @Test
    func clickingChipsInTheSidePanesResolvesTheConflict() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }
            try await hosted.settle()
            let block = try conflictID(model)
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result"))

            try click("left", block: block, in: hosted, pane: "left")
            try await eventually(timeout: .seconds(20)) { model.merge?.conflictCount == 0 }
            #expect(model.summary == "All conflicts resolved")
            try await eventually(timeout: .seconds(20)) { result.string == paneText(resolvedLeftResult) }

            try click("right", block: block, in: hosted, pane: "right")
            try await eventually { result.string == paneText(resolvedRightResult) }

            try click("ignore", block: block, in: hosted, pane: "left")
            try await eventually { result.string.contains("epsilon\nzeta\neta") }
            #expect(model.merge?.isFullyResolved == true)
            #expect(hosted.renders())
        }
    }

    @Test
    func toolbarActionsApplyNonConflictingChangesFromEachSide() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }
            try await hosted.settle()
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result"))

            view.applyLeft()
            let leftOnly = "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\n"
            try await eventually(timeout: .seconds(20)) { result.string == paneText(leftOnly) }

            view.applyRight()
            let rightOnly = "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"
            try await eventually(timeout: .seconds(20)) { model.resultText == rightOnly }
            try await eventually(timeout: .seconds(20)) { result.string == paneText(rightOnly) }

            view.applyAll()
            let both = "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"
            try await eventually(timeout: .seconds(20)) { model.resultText == both }
            try await eventually(timeout: .seconds(20)) { result.string == paneText(both) }
        }
    }

    @Test
    func handlingChipsResolvesBlocksThroughTheModel() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            let block = try conflictID(model)

            view.handle(MergePaneChip(kind: .acceptRight, blockID: block))
            try await eventually(timeout: .seconds(20)) { model.resultText == resolvedRightResult }
            view.handle(MergePaneChip(kind: .acceptLeft, blockID: block))
            try await eventually(timeout: .seconds(20)) { model.resultText == resolvedLeftResult }
            view.handle(MergePaneChip(kind: .ignore, blockID: block))
            try await eventually(timeout: .seconds(20)) { model.resultText.contains("epsilon\nzeta\neta") }
        }
    }

    @Test
    func resolvedMergeShowsTheSuccessSummary() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()
            let conflictedSnapshot = hosted.snapshot()

            let block = try conflictID(model)
            view.handle(MergePaneChip(kind: .acceptLeft, blockID: block))
            try await eventually(timeout: .seconds(20)) { model.merge?.isFullyResolved == true }
            try await hosted.settle()

            #expect(model.summary == "All conflicts resolved")
            #expect(model.hasUnresolvedConflicts == false)
            #expect(HostedView.pixelsDiffer(conflictedSnapshot, hosted.snapshot()))
        }
    }

    @Test
    func missingConflictShowsTheErrorBannerWithEmptyPanes() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: "no/such/file.txt")
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.errorMessage == "Conflict is not valid and no longer can be resolved.")
            #expect(model.merge == nil)
            #expect(model.isLoading == false)
            #expect(model.canApply == false)
            #expect(model.canAcceptSide == false)
            #expect(model.summary.isEmpty)
            #expect(model.canApplyNonConflicting(.left) == false)
            #expect(hosted.views(of: NSTextView.self).count == 3)
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result"))
            #expect(result.string.isEmpty)
            #expect(hosted.renders())

            view.applyAll()
            view.handle(MergePaneChip(kind: .acceptLeft, blockID: 0))
            #expect(model.merge == nil)
        }
    }

    @Test
    func deleteConflictRendersAnEmptyLeftPane() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.deleteModifyConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: "gone.txt")
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()

            let left = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "left"))
            let right = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "right"))
            #expect(left.string.isEmpty)
            #expect(right.string.contains("modified by feature"))
            #expect(hosted.renders())
        }
    }

    @Test
    func rebaseConflictRendersSwappedSides() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.rebaseConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: "src/main.swift")
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()

            let left = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "left"))
            let right = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "right"))
            #expect(left.string.contains("feature-line"))
            #expect(right.string.contains("main-line"))
            #expect(model.leftTitle == "Your commits, branch feature")
            #expect(model.rightTitle == "Changes from branch main")
        }
    }

    @Test
    func typingInTheResultPaneMarksTheResultEdited() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result"))
            #expect(model.isResultEdited == false)

            result.insertText("typed ", replacementRange: NSRange(location: 0, length: 0))

            #expect(model.isResultEdited)
            #expect(model.resultText.hasPrefix("typed alpha"))
        }
    }

    @Test
    func savingShowsTheProgressIndicatorInTheBottomBar() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()

            let task = Task { await model.apply() }
            var sawSaving = false
            for _ in 0..<5000 where !sawSaving {
                if model.isSaving {
                    sawSaving = true
                } else {
                    await Task.yield()
                }
            }
            #expect(sawSaving)
            #expect(model.canApply == false)
            _ = view.body
            hosted.layout()

            #expect(await task.value)
            #expect(model.isSaving == false)
            #expect(try await fixture.isFullyStaged(configPath))
        }
    }

    @Test
    func applyClosesAfterConfirmingUnresolvedConflicts() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }

            mergeRevisionsCoverageAnswering(false) { view.apply() }
            try await Task.sleep(for: .milliseconds(200))
            #expect(counter.count == 0)
            #expect(fixture.hasConflictMarkers(configPath))

            mergeRevisionsCoverageAnswering(true) { view.apply() }
            try await eventually { counter.count == 1 }
            #expect(fixture.hasConflictMarkers(configPath) == false)
            #expect(try await fixture.isFullyStaged(configPath))
        }
    }

    @Test
    func acceptLeftClosesAfterStagingOurSide() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }
            model.userEditedResult("draft\n")

            mergeRevisionsCoverageAnswering(false) { view.acceptLeft() }
            try await Task.sleep(for: .milliseconds(200))
            #expect(counter.count == 0)
            #expect(try await fixture.unmergedPaths() == [configPath, notesPath])

            mergeRevisionsCoverageAnswering(true) { view.acceptLeft() }
            try await eventually { counter.count == 1 }
            #expect(try fixture.read(configPath).contains("zeta-main"))
            #expect(try await fixture.isFullyStaged(configPath))
        }
    }

    @Test
    func acceptRightClosesAfterStagingTheirSide() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }

            view.acceptRight()

            try await eventually { counter.count == 1 }
            #expect(try fixture.read(configPath).contains("zeta-feature"))
            #expect(try await fixture.isFullyStaged(configPath))
        }
    }

    @Test
    func cancelClosesImmediatelyWithoutEditsAndAsksWithEdits() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await mergeRevisionsCoverageModel(root: dir, path: configPath)
            let counter = MergeRevisionsCoverageCloseCounter()
            let (view, hosted) = mergeRevisionsCoverageHost(model, counter: counter)
            defer { hosted.close() }

            view.cancel()
            try await eventually { counter.count == 1 }

            model.userEditedResult("draft\n")
            mergeRevisionsCoverageAnswering(false) { view.cancel() }
            try await Task.sleep(for: .milliseconds(200))
            #expect(counter.count == 1)
            #expect(model.isResultEdited)

            mergeRevisionsCoverageAnswering(true) { view.cancel() }
            try await eventually { counter.count == 2 }
            #expect(model.isResultEdited == false)
            #expect(fixture.hasConflictMarkers(configPath))
        }
    }

    @Test
    func scrollingOnePaneScrollsTheOtherTwo() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            let base = (0..<300).map { "line \($0)" }
            try fixture.write("long.txt", base.joined(separator: "\n") + "\n")
            try await fixture.commit("base")
            try await fixture.run("checkout", "-q", "-b", "feature")
            var featureLines = base
            featureLines[250] = "feature change"
            try fixture.write("long.txt", featureLines.joined(separator: "\n") + "\n")
            try await fixture.commit("feature")
            try await fixture.run("checkout", "-q", "main")
            var mainLines = base
            mainLines[250] = "main change"
            mainLines[5] = "main top"
            try fixture.write("long.txt", mainLines.joined(separator: "\n") + "\n")
            try await fixture.commit("main")
            _ = try await fixture.runIgnoringFailure("merge", "feature")

            let model = try await mergeRevisionsCoverageModel(root: dir, path: "long.txt")
            let (_, hosted) = mergeRevisionsCoverageHost(model, counter: MergeRevisionsCoverageCloseCounter())
            defer { hosted.close() }
            try await hosted.settle()
            let left = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "left")?.enclosingScrollView)
            let result = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "result")?.enclosingScrollView)
            let right = try #require(mergeRevisionsCoverageTextView(in: hosted, pane: "right")?.enclosingScrollView)

            left.contentView.scroll(to: NSPoint(x: 0, y: 200))
            left.reflectScrolledClipView(left.contentView)

            try await eventually {
                result.contentView.bounds.origin.y > 0 && right.contentView.bounds.origin.y > 0
            }
        }
    }
}

@MainActor
@Suite(.uiGate)
struct MergeRevisionsWindowCoverageTests {
    private let configPath = "app/config.txt"

    private func makeController(
        _ root: URL,
        load: Bool = true
    ) async throws -> (MergeRevisionsWindowController, MergeRevisionsCoverageCloseCounter) {
        let model = try await mergeRevisionsCoverageModel(root: root, path: configPath, load: load)
        let controller = MergeRevisionsWindowController(model: model)
        let counter = MergeRevisionsCoverageCloseCounter()
        controller.onClose = { counter.count += 1 }
        return (controller, counter)
    }

    @Test
    func windowIsConfiguredLikeTheIntelliJMergeDialog() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir, load: false)
            let window = try #require(controller.window)
            defer { window.close() }

            #expect(window.title == "Merge Revisions for app/config.txt")
            #expect(window.appearance?.name == .darkAqua)
            #expect(window.contentMinSize == NSSize(width: 720, height: 460))
            #expect(window.isReleasedWhenClosed == false)
            #expect(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
            #expect(window.delegate === controller)
            #expect((window.contentView?.frame.width ?? 0) >= 720)
            #expect(window.contentViewController is NSHostingController<MergeRevisionsView>)
            #expect(controller.model.path == configPath)
        }
    }

    @Test
    func placeCentersOverTheParentInsideTheScreen() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir, load: false)
            let window = try #require(controller.window)
            defer { window.close() }
            let parent = NSWindow(
                contentRect: NSRect(x: 600, y: 400, width: 500, height: 400),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            parent.isReleasedWhenClosed = false
            defer { parent.close() }

            controller.place(relativeTo: parent)

            if let screen = parent.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                if visible.width >= window.frame.width + 24, visible.height >= window.frame.height + 24 {
                    #expect(visible.insetBy(dx: 12, dy: 12).contains(window.frame))
                }
            } else {
                #expect(window.frame.midX == parent.frame.midX)
                #expect(window.frame.midY == parent.frame.midY)
            }
        }
    }

    @Test
    func placeWithoutAParentUsesTheMainScreen() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir, load: false)
            let window = try #require(controller.window)
            defer { window.close() }

            controller.place(relativeTo: nil)

            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                if visible.width >= window.frame.width + 24, visible.height >= window.frame.height + 24 {
                    #expect(visible.insetBy(dx: 12, dy: 12).contains(window.frame))
                }
            } else {
                #expect(window.frame.origin == .zero)
            }
        }
    }

    @Test
    func placeWithoutAWindowDoesNothing() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir, load: false)
            controller.window?.close()
            controller.window = nil

            controller.place(relativeTo: nil)

            #expect(controller.window == nil)
        }
    }

    @Test
    func closingWithoutEditsIsImmediateAndNotifiesTheOwner() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, counter) = try await makeController(dir)
            let window = try #require(controller.window)
            window.orderFront(nil)

            #expect(controller.windowShouldClose(window))
            window.performClose(nil)

            #expect(counter.count == 1)
            #expect(window.isVisible == false)
        }
    }

    @Test
    func closingWithEditsAsksBeforeClosing() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, counter) = try await makeController(dir)
            let window = try #require(controller.window)
            window.orderFront(nil)
            defer { window.close() }
            controller.model.userEditedResult("draft\n")

            let declined = mergeRevisionsCoverageAnswering(false) { controller.windowShouldClose(window) }
            #expect(declined == false)
            try await Task.sleep(for: .milliseconds(200))
            #expect(counter.count == 0)
            #expect(window.isVisible)
            #expect(controller.model.isResultEdited)

            let confirmed = mergeRevisionsCoverageAnswering(true) { controller.windowShouldClose(window) }
            #expect(confirmed == false)
            try await eventually { counter.count == 1 }
            #expect(window.isVisible == false)
            #expect(controller.model.isResultEdited == false)
        }
    }

    @Test
    func theRootViewClosesTheWindowThroughItsCloseHandler() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, counter) = try await makeController(dir)
            let window = try #require(controller.window)
            window.orderFront(nil)
            defer { window.close() }
            let hosting = try #require(window.contentViewController as? NSHostingController<MergeRevisionsView>)

            hosting.rootView.onClose()

            #expect(counter.count == 1)
            #expect(window.isVisible == false)
        }
    }

    @Test
    func cancelFromTheRootViewClosesTheWindow() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, counter) = try await makeController(dir)
            let window = try #require(controller.window)
            window.orderFront(nil)
            defer { window.close() }
            let hosting = try #require(window.contentViewController as? NSHostingController<MergeRevisionsView>)

            hosting.rootView.cancel()

            try await eventually { counter.count == 1 }
            #expect(window.isVisible == false)
        }
    }

    @Test
    func decodingFromACoderIsNotSupported() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)

        #expect(MergeRevisionsWindowController(coder: decoder) == nil)
    }
}
