import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WelcomeViewModelTests {
    private let home = "/Users/me"

    private func makeModel(
        _ defaults: UserDefaults,
        paths: [String],
        recorder: WelcomeRecorder
    ) -> WelcomeViewModel {
        WelcomeViewModel(
            manager: makeWelcomeManager(defaults, paths: paths),
            services: recorder.services(),
            home: home
        )
    }

    @Test
    func theFirstProjectIsSelectedInitially() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: ["/Users/me/a", "/Users/me/b"], recorder: WelcomeRecorder())

        #expect(model.selection == "/Users/me/a")
        #expect(model.selectedProject?.displayName == "a")
        #expect(model.isEmptyState == false)
        #expect(model.projects.map(\.displayName) == ["a", "b"])
        #expect(model.selectedTab == .projects)
        #expect(WelcomeTab.projects.title == "Projects")
        #expect(WelcomeTab.projects.id == "projects")
    }

    @Test
    func anEmptyListIsTheEmptyStateWithoutSelection() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: [], recorder: WelcomeRecorder())

        #expect(model.isEmptyState)
        #expect(model.selection == nil)
        #expect(model.selectedProject == nil)
        model.moveSelection(by: 1)
        #expect(model.selection == nil)
    }

    @Test
    func theApplicationIdentityComesFromTheBundle() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: [], recorder: WelcomeRecorder())

        #expect(model.appName == Bundle.displayName)
        #expect(model.appVersion.hasPrefix("Version "))
    }

    @Test
    func theQueryFiltersByNameAndPathAndSelectsTheFirstMatch() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(
            defaults,
            paths: ["/Users/me/code/alpha", "/Users/me/work/beta", "/opt/gamma"],
            recorder: WelcomeRecorder()
        )

        model.updateQuery("work")
        #expect(model.query == "work")
        #expect(model.projects.map(\.displayName) == ["beta"])
        #expect(model.selection == "/Users/me/work/beta")

        model.updateQuery("gam")
        #expect(model.projects.map(\.displayName) == ["gamma"])
        #expect(model.selection == "/opt/gamma")

        model.updateQuery("zzzqq")
        #expect(model.projects.isEmpty)
        #expect(model.selection == nil)
        #expect(model.isEmptyState == false)

        model.updateQuery("")
        #expect(model.projects.count == 3)
        #expect(model.selection == "/Users/me/code/alpha")
    }

    @Test
    func reconcilingKeepsAValidSelectionAndRepairsAStaleOne() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: ["/Users/me/a", "/Users/me/b"], recorder: WelcomeRecorder())

        model.selection = "/Users/me/b"
        model.reconcileSelection()
        #expect(model.selection == "/Users/me/b")

        model.selection = "/gone"
        model.reconcileSelection()
        #expect(model.selection == "/Users/me/a")
    }

    @Test
    func arrowsMoveTheSelectionWithinTheBounds() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: ["/p/a", "/p/b", "/p/c"], recorder: WelcomeRecorder())

        model.moveSelection(by: -1)
        #expect(model.selection == "/p/a")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        #expect(model.selection == "/p/c")
        model.moveSelection(by: -1)
        #expect(model.selection == "/p/b")

        model.selection = nil
        model.moveSelection(by: 1)
        #expect(model.selection == "/p/a")
        model.selection = nil
        model.moveSelection(by: -1)
        #expect(model.selection == "/p/c")
    }

    @Test
    func returnOpensTheSelectionAndClosesTheWelcomeWindow() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a", "/p/b"], recorder: recorder)

        model.perform(.moveDown)
        model.perform(.moveUp)
        model.perform(.moveDown)
        model.perform(.open)

        #expect(recorder.opened == [URL(filePath: "/p/b", directoryHint: .isDirectory)])
        #expect(recorder.dismissals == 1)
    }

    @Test
    func returnWithoutASelectionOpensNothing() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)

        model.perform(.open)

        #expect(recorder.opened.isEmpty)
        #expect(recorder.dismissals == 0)
    }

    @Test
    func theWindowStaysOpenUntilTheDocumentOpens() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        recorder.completesOpens = false
        let model = makeModel(defaults, paths: ["/p/a"], recorder: recorder)

        model.openSelection()

        #expect(recorder.opened.count == 1)
        #expect(recorder.dismissals == 0)
    }

    @Test
    func deleteRemovesTheSelectionAfterConfirmationAndSelectsTheNext() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a", "/p/b"], recorder: recorder)

        model.perform(.remove)

        #expect(recorder.confirmed.map(\.path) == ["/p/a"])
        #expect(model.manager.recentPaths == ["/p/b"])
        #expect(model.selection == "/p/b")

        model.perform(.remove)
        #expect(model.manager.recentPaths.isEmpty)
        #expect(model.isEmptyState)
        #expect(model.selection == nil)
    }

    @Test
    func aDeclinedConfirmationKeepsTheProject() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        recorder.confirmationAnswer = false
        let model = makeModel(defaults, paths: ["/p/a"], recorder: recorder)

        model.removeSelection()

        #expect(recorder.confirmed.count == 1)
        #expect(model.manager.recentPaths == ["/p/a"])
        #expect(model.selection == "/p/a")
    }

    @Test
    func deleteWithoutASelectionAsksNothing() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)

        model.removeSelection()

        #expect(recorder.confirmed.isEmpty)
    }

    @Test
    func removingAnotherRowKeepsTheSelection() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: ["/p/a", "/p/b", "/p/c"], recorder: WelcomeRecorder())
        model.selection = "/p/c"
        let second = try #require(model.projects.first { $0.path == "/p/b" })

        model.remove(second)

        #expect(model.manager.recentPaths == ["/p/a", "/p/c"])
        #expect(model.selection == "/p/c")
    }

    @Test
    func copyPathUsesTheInjectedWriter() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a b"], recorder: recorder)
        let project = try #require(model.selectedProject)

        model.copyPath(of: project)

        #expect(recorder.copied == ["/p/a b"])
    }

    @Test
    func revealPassesTheProjectLocation() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a"], recorder: recorder)
        let project = try #require(model.selectedProject)

        model.reveal(project)

        #expect(recorder.revealed == [[project.url]])
    }

    @Test
    func theToolbarActionsDismissTheWindowWhenTheyComplete() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)

        model.newProject()
        model.openFromDisk()

        #expect(recorder.newProjectCalls == 1)
        #expect(recorder.openFromDiskCalls == 1)
        #expect(recorder.dismissals == 2)
    }

    @Test
    func droppedURLsAreOpenedAndReportedAsHandled() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)
        let urls = [URL(filePath: "/p/x"), URL(filePath: "/p/y")]

        #expect(model.open(urls: urls))
        #expect(model.open(urls: []) == false)

        #expect(recorder.opened == urls)
    }

    @Test
    func theCloneFlowFlagsAreSet() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: [], recorder: WelcomeRecorder())

        model.showCloneSheet()
        model.showCheckoutBranch(for: URL(filePath: "/p/cloned"))

        #expect(model.isCloneSheetPresented)
        #expect(model.checkoutBranchURL == URL(filePath: "/p/cloned"))
    }

    @Test
    func refreshResetsTheQueryAndDropsMissingProjects() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let kept = directory.appending(path: "kept", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
            let missing = directory.appending(path: "missing", directoryHint: .isDirectory)
            let manager = RecentProjectsManager(defaults: defaults)
            manager.markRecent(at: kept, isDirectory: true)
            manager.markRecent(at: missing, isDirectory: true)
            let model = WelcomeViewModel(manager: manager, services: WelcomeRecorder().services(), home: home)
            model.updateQuery("kept")

            await model.refresh()

            #expect(model.query.isEmpty)
            #expect(model.projects.map(\.displayName) == ["kept"])
            #expect(model.selection == RecentProjectsManager.normalizedPath(of: kept))
        }
    }

    @Test
    func theDefaultHomeDirectoryIsTheCurrentUsersHome() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let model = WelcomeViewModel(manager: RecentProjectsManager(defaults: defaults), services: .live)

        #expect(model.home == NSHomeDirectory())
    }

    @Test
    func theDefaultServicesAreTheLiveOnes() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let model = WelcomeViewModel(manager: RecentProjectsManager(defaults: defaults))

        #expect(model.services.makeCloneViewModel().isCloning == false)
    }

    @Test
    func theVersionTextFallsBackToEmptyParts() {
        #expect(WelcomeViewModel.versionText(version: "1.2", postfix: "-beta") == "Version 1.2-beta")
        #expect(WelcomeViewModel.versionText(version: nil, postfix: nil) == "Version ")
    }

    @Test
    func theCloneFlowActionsShowTheBranchChooserAndOpenTheDocument() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)
        let cloned = URL(filePath: "/p/cloned")

        model.showCheckoutBranchAction(cloned)
        model.openDocumentAction(cloned)

        #expect(model.checkoutBranchURL == cloned)
        #expect(recorder.opened == [cloned])
        #expect(recorder.dismissals == 1)
    }

    @Test
    func submittingTheSearchOpensTheSelection() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a"], recorder: recorder)

        model.submitSearchAction()

        #expect(recorder.opened == [URL(filePath: "/p/a", directoryHint: .isDirectory)])
    }
}
