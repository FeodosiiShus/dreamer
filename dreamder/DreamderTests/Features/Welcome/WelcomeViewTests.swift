import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WelcomeViewTests {
    private func host(_ model: WelcomeViewModel) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: WelcomeMetrics.windowWidth, height: WelcomeMetrics.windowHeight)) {
            WelcomeView(model: model)
        }
    }

    private func makeDirectories(in directory: URL, count: Int) throws -> [URL] {
        try (0..<count).map { index in
            let url = directory.appending(path: "project\(index)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    private func makeModel(
        _ defaults: UserDefaults,
        directories: [URL],
        files: [URL] = [],
        recorder: WelcomeRecorder = WelcomeRecorder()
    ) -> WelcomeViewModel {
        let manager = RecentProjectsManager(defaults: defaults)
        for file in files {
            manager.markRecent(at: file, isDirectory: false)
        }
        for url in directories {
            manager.markRecent(at: url, isDirectory: true)
        }
        return WelcomeViewModel(manager: manager, services: recorder.services(), home: NSHomeDirectory())
    }

    @Test
    func noRecentsShowTheEmptyState() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, directories: [])
        let hosted = host(model)
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(model.isEmptyState)
        #expect(hosted.renders())
    }

    @Test
    func threeRecentsShowTheList() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let (emptyDefaults, emptySuiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(emptyDefaults, suiteName: emptySuiteName) }
        try await withTempDir { directory in
            let file = directory.appending(path: "notes.txt")
            try Data("x".utf8).write(to: file)
            let model = makeModel(defaults, directories: try makeDirectories(in: directory, count: 2), files: [file])
            let empty = host(makeModel(emptyDefaults, directories: []))
            defer { empty.close() }
            let hosted = host(model)
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(150))
            try await empty.settle(.milliseconds(150))

            #expect(model.projects.count == 3)
            #expect(model.isEmptyState == false)
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(hosted.snapshot(), empty.snapshot()))
        }
    }

    @Test
    func sixtyRecentsKeepTheFiftyNewestAndScrollWithTheSelection() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let model = makeModel(defaults, directories: try makeDirectories(in: directory, count: 60))
            let hosted = host(model)
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(150))
            let top = hosted.snapshot()
            for _ in 0..<49 { model.moveSelection(by: 1) }
            try await hosted.settle(.milliseconds(150))

            #expect(model.projects.count == RecentProjectsManager.maxRecentProjects)
            #expect(model.selection == model.projects.last?.path)
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(top, hosted.snapshot()))
        }
    }

    @Test
    func filteringReplacesTheListWithAMessageWhenNothingMatches() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let model = makeModel(defaults, directories: try makeDirectories(in: directory, count: 3))
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))
            let unfiltered = hosted.snapshot()

            model.updateQuery("zzzqq")
            try await hosted.settle(.milliseconds(150))
            let nothing = hosted.snapshot()
            model.updateQuery("project1")
            try await hosted.settle(.milliseconds(150))
            let single = hosted.snapshot()

            #expect(model.projects.map(\.displayName) == ["project1"])
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(unfiltered, nothing))
            #expect(HostedView.pixelsDiffer(nothing, single))
        }
    }

    @Test
    func movingTheSelectionRepaintsTheRows() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let model = makeModel(defaults, directories: try makeDirectories(in: directory, count: 3))
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))
            let first = hosted.snapshot()

            model.perform(.moveDown)
            try await hosted.settle(.milliseconds(150))

            #expect(HostedView.pixelsDiffer(first, hosted.snapshot()))
        }
    }

    @Test
    func hostingStylesTheWindowLikeTheWelcomeFrame() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeMetrics.windowWidth, height: WelcomeMetrics.windowHeight),
            styleMask: [.titled, .resizable, .miniaturizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.contentView = NSHostingView(rootView: WelcomeView(model: makeModel(defaults, directories: [])))

        try await eventually(timeout: .seconds(30)) { window.titlebarAppearsTransparent }
        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
        #expect(window.isMovableByWindowBackground)
    }

    @Test
    func theCloneSheetsAreBuiltFromTheModelFlags() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let model = makeModel(defaults, directories: [])
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            model.showCloneSheet()
            try await hosted.settle(.milliseconds(300))
            model.isCloneSheetPresented = false
            try await hosted.settle(.milliseconds(300))
            model.showCheckoutBranch(for: directory)
            try await hosted.settle(.milliseconds(300))
            model.checkoutBranchURL = nil
            try await hosted.settle(.milliseconds(300))

            #expect(model.isCloneSheetPresented == false)
            #expect(model.checkoutBranchURL == nil)
            #expect(hosted.renders())
        }
    }

    @Test
    func theWindowStyleCanBeAppliedToAnyWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .resizable, .miniaturizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        WelcomeWindowStyle.apply(to: window)

        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    }

    @Test
    func theObserverViewStylesItsWindowWhenAttached() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let observer = WelcomeWindowObserverView(frame: .zero)

        #expect(window.styleMask.contains(.resizable))

        window.contentView?.addSubview(observer)

        #expect(window.styleMask.contains(.resizable) == false)
    }
}
