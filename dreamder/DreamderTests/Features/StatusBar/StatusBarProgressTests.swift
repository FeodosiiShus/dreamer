import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StatusBarProgressTests {
    private func note(
        _ id: String,
        title: String = "Task",
        message: String? = nil,
        percentage: Double? = nil,
        isLoading: Bool = false
    ) -> TaskNotificationModel {
        TaskNotificationModel(id: id, title: title, message: message, percentage: percentage, isLoading: isLoading)
    }

    private func post(
        _ center: NotificationCenter,
        _ action: TaskNotificationHandler.Action,
        id: String,
        title: String? = nil,
        message: String? = nil,
        percentage: Double? = nil,
        isLoading: Bool? = nil,
        workspace: URL? = nil
    ) {
        var info: [String: Any] = ["id": id, "action": action.rawValue]
        info["title"] = title
        info["message"] = message
        info["percentage"] = percentage
        info["isLoading"] = isLoading
        info["workspace"] = workspace
        center.post(name: .taskNotification, object: nil, userInfo: info)
    }

    private func host(_ handler: TaskNotificationHandler) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 420, height: 30)) {
            StatusBarProgressIndicator(handler: handler)
                .padding(4)
                .background(Color.black)
        }
    }

    @Test
    func modelSummarisesEmptySingleAndMultipleNotifications() {
        let empty = StatusBarProgressModel(notifications: [])
        #expect(empty.isEmpty)
        #expect(empty.first == nil)
        #expect(empty.extraCount == 0)
        #expect(empty.counterText == nil)
        #expect(empty.summaryHelp == "")

        let single = StatusBarProgressModel(notifications: [note("a", title: "Indexing")])
        #expect(!single.isEmpty)
        #expect(single.first?.title == "Indexing")
        #expect(single.counterText == nil)
        #expect(single.summaryHelp == "Indexing")

        let several = StatusBarProgressModel(notifications: [note("a"), note("b"), note("c")])
        #expect(several.extraCount == 2)
        #expect(several.counterText == "+2")
        #expect(several.summaryHelp == "3 processes running")
    }

    @Test
    func fractionIsClampedAndIndeterminateNeedsLoadingWithoutPercentage() {
        #expect(StatusBarProgressModel.fraction(of: note("a", percentage: 0.25)) == 0.25)
        #expect(StatusBarProgressModel.fraction(of: note("a", percentage: 3)) == 1)
        #expect(StatusBarProgressModel.fraction(of: note("a", percentage: -1)) == 0)
        #expect(StatusBarProgressModel.fraction(of: note("a")) == nil)

        #expect(StatusBarProgressModel.isIndeterminate(note("a", isLoading: true)))
        #expect(!StatusBarProgressModel.isIndeterminate(note("a", percentage: 0.5, isLoading: true)))
        #expect(!StatusBarProgressModel.isIndeterminate(note("a")))
    }

    @Test
    func presenterShowsThePopoverOnlyWhileThereAreNotifications() {
        let presenter = StatusBarProgressPresenter()
        #expect(!presenter.isPresented(hasNotifications: true))

        presenter.toggle()
        #expect(presenter.isPresented(hasNotifications: true))
        #expect(!presenter.isPresented(hasNotifications: false))

        presenter.emptinessChanged(false, false)
        #expect(presenter.isRequested)

        presenter.emptinessChanged(false, true)
        #expect(!presenter.isRequested)

        presenter.setPresented(true)
        #expect(presenter.isRequested)
        presenter.toggle()
        #expect(!presenter.isRequested)
    }

    @Test
    func popoverBindingFollowsThePresenterAndTheNotifications() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)
        let presenter = StatusBarProgressPresenter(isRequested: true)
        let indicator = StatusBarProgressIndicator(handler: handler, presenter: presenter)
        #expect(indicator.popoverBinding.wrappedValue == false)

        post(center, .create, id: "a", title: "Indexing", isLoading: true)
        try await eventually { !handler.notifications.isEmpty }
        #expect(indicator.popoverBinding.wrappedValue)

        indicator.popoverBinding.wrappedValue = false
        #expect(!presenter.isRequested)
        #expect(indicator.model.first?.title == "Indexing")
    }

    @Test
    func widgetRendersNothingThenEachNotificationShape() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)
        let hosted = host(handler)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        let empty = hosted.snapshot()

        post(center, .create, id: "a", title: "Indexing project", percentage: 0.4, isLoading: true)
        try await eventually {
            hosted.layout()
            return HostedView.pixelsDiffer(empty, hosted.snapshot())
        }
        let determinate = hosted.snapshot()

        post(center, .update, id: "a", percentage: 0.9)
        try await eventually {
            hosted.layout()
            return HostedView.pixelsDiffer(determinate, hosted.snapshot())
        }

        post(center, .delete, id: "a")
        post(center, .create, id: "b", title: "Indexing project", isLoading: true)
        try await eventually { handler.notifications.map(\.id) == ["b"] }
        try await hosted.settle(.milliseconds(50))
        let indeterminate = hosted.snapshot()
        #expect(HostedView.pixelsDiffer(determinate, indeterminate))

        post(center, .create, id: "c", title: "Second", isLoading: true)
        post(center, .create, id: "d", title: "Third", isLoading: true)
        try await eventually { handler.notifications.count == 3 }
        try await hosted.settle(.milliseconds(50))
        #expect(HostedView.pixelsDiffer(indeterminate, hosted.snapshot()))

        post(center, .delete, id: "b")
        post(center, .delete, id: "c")
        post(center, .delete, id: "d")
        try await eventually { handler.notifications.isEmpty }
        try await hosted.settle(.milliseconds(50))
        #expect(!HostedView.pixelsDiffer(empty, hosted.snapshot()))
    }

    @Test
    func hoveringTheProgressWidgetPaintsTheStatusBarHoverBackground() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)
        post(center, .create, id: "a", title: "Indexing project", percentage: 0.4, isLoading: true)
        try await eventually { !handler.notifications.isEmpty }
        let idle = HostedViewFixture.host(size: NSSize(width: 420, height: 30)) {
            StatusBarProgressIndicator(handler: handler)
        }
        let hovered = HostedViewFixture.host(size: NSSize(width: 420, height: 30)) {
            StatusBarProgressIndicator(handler: handler, isHovering: true)
        }
        defer {
            idle.close()
            hovered.close()
        }
        try await idle.settle(.milliseconds(50))
        try await hovered.settle(.milliseconds(50))

        #expect(idle.renders())
        #expect(HostedView.pixelsDiffer(idle.snapshot(), hovered.snapshot()))
    }

    @Test
    func popoverListsEveryNotificationWithItsProgress() async throws {
        let handler = TaskNotificationHandler(center: NotificationCenter())
        let indicator = StatusBarProgressIndicator(handler: handler)
        let plain = HostedViewFixture.host(size: NSSize(width: 340, height: 220)) {
            StatusBarProgressPopover(notifications: [])
        }
        let populated = HostedViewFixture.host(size: NSSize(width: 340, height: 220)) {
            StatusBarProgressPopover(notifications: [
                note("a", title: "Determinate", message: "halfway", percentage: 0.5, isLoading: true),
                note("b", title: "Indeterminate", isLoading: true),
                note("c", title: "Static")
            ])
        }
        let content = HostedViewFixture.host(size: NSSize(width: 340, height: 220)) {
            indicator.popoverContent()
        }
        defer {
            plain.close()
            populated.close()
            content.close()
        }
        try await plain.settle(.milliseconds(50))
        try await populated.settle(.milliseconds(50))
        try await content.settle(.milliseconds(50))

        #expect(populated.renders())
        #expect(HostedView.pixelsDiffer(plain.snapshot(), populated.snapshot()))
    }

    @Test
    func postedWorkspaceTasksShowUpdateAndDisappearInTheStatusBarModel() async throws {
        let url = URL(fileURLWithPath: "/status-bar-progress/\(UUID().uuidString)", isDirectory: true)
        let handler = TaskNotificationHandler(workspaceURL: url)
        let id = "status-bar-progress-\(UUID().uuidString)"
        func mine() -> StatusBarProgressModel {
            StatusBarProgressModel(notifications: handler.notifications.filter { $0.id == id })
        }
        #expect(mine().isEmpty)

        TaskNotificationHandler.postTask(
            toWorkspace: url,
            action: .create,
            model: TaskNotificationModel(id: id, title: "Installing", message: "step 1", isLoading: true)
        )
        try await eventually { mine().first?.title == "Installing" }
        let created = try #require(mine().first)
        #expect(StatusBarProgressModel.isIndeterminate(created))

        TaskNotificationHandler.postTask(
            toWorkspace: url,
            action: .update,
            model: TaskNotificationModel(id: id, title: "Installing", message: "step 2", percentage: 0.5, isLoading: true)
        )
        try await eventually { mine().first.flatMap(StatusBarProgressModel.fraction) == 0.5 }

        TaskNotificationHandler.postTask(
            toWorkspace: url,
            action: .delete,
            model: TaskNotificationModel(id: id, title: "Installing")
        )
        try await eventually { mine().isEmpty }
    }

    @Test
    func statusBarShowsTheProgressOfItsWorkspaceOnly() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let url = try #require(workspace.taskNotificationHandler.workspaceURL)
            let center = NotificationCenter()
            let handler = TaskNotificationHandler(workspaceURL: url, center: center)
            workspace.taskNotificationHandler = handler
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 900, height: 40)) {
                StatusBarView()
            }
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            post(center, .create, id: "foreign", title: "Foreign", isLoading: true, workspace: url.appending(path: "elsewhere"))
            post(center, .create, id: "own", title: "Indexing project", percentage: 0.3, isLoading: true, workspace: url)
            try await eventually { handler.notifications.map(\.id) == ["own"] }
            try await eventually {
                hosted.layout()
                return HostedView.pixelsDiffer(idle, hosted.snapshot())
            }
        }
    }
}
