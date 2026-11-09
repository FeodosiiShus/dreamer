import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SafeModeNotifierTests {
    @MainActor
    private final class Recorder {
        let manager = NotificationManager(center: NotificationsFakeCenter(), notificationCenter: NotificationCenter())
        var restarted: [String] = []
        var asked: [URL] = []
        var answer: Bool

        init(answer: Bool) {
            self.answer = answer
        }

        func restart(_ workspacePath: String) async {
            restarted.append(workspacePath)
        }

        func confirm(_ root: URL) async -> Bool {
            asked.append(root)
            return answer
        }
    }

    private func makeNotifier(_ recorder: Recorder, defaults: UserDefaults) -> (SafeModeNotifier, WorkspaceTrust) {
        let trust = WorkspaceTrust(defaults: defaults, confirm: { await recorder.confirm($0) })
        let notifier = SafeModeNotifier(
            notifications: { recorder.manager },
            trust: { trust },
            restartServers: { await recorder.restart($0) }
        )
        return (notifier, trust)
    }

    @Test
    func announcingPostsAStickySafeModeNotificationNamingTheSkippedServer() async throws {
        try await withIsolatedDefaults { defaults in
            let recorder = Recorder(answer: false)
            let (notifier, _) = makeNotifier(recorder, defaults: defaults)

            notifier.announce(workspacePath: "/ws", executable: "/ws/node_modules/.bin/typescript-language-server")
            try await eventually { recorder.manager.notifications.count == 1 }

            let notification = try #require(recorder.manager.notifications.first)
            #expect(notification.title == "Project is in Safe Mode")
            #expect(notification.description.contains("typescript-language-server"))
            #expect(!notification.description.contains("node_modules"))
            #expect(notification.actionButtonTitle == "Trust Project\u{2026}")
            #expect(notification.isSticky)
        }
    }

    @Test
    func theDiscoveryNoticePostsOncePerWorkspace() async throws {
        try await withIsolatedDefaults { defaults in
            let recorder = Recorder(answer: false)
            let (notifier, _) = makeNotifier(recorder, defaults: defaults)
            let notice = UntrustedWorkspaceServerNotice(
                report: UntrustedWorkspaceServerNotice.makeReport(notifier: { notifier })
            )

            notice.note(workspacePath: "/one", executable: "/one/venv/bin/pylsp")
            notice.note(workspacePath: "/one", executable: "/one/venv/bin/pylsp")
            notice.note(workspacePath: "/two", executable: "/two/venv/bin/pylsp")
            try await eventually { recorder.manager.notifications.count == 2 }
            await lspServiceFlushMainQueue()

            #expect(recorder.manager.notifications.count == 2)
        }
    }

    @Test
    func grantingTrustFromTheActionRestartsTheWorkspaceServers() async throws {
        try await withIsolatedDefaults { defaults in
            let recorder = Recorder(answer: true)
            let (notifier, trust) = makeNotifier(recorder, defaults: defaults)
            notifier.announce(workspacePath: "/ws", executable: "/ws/venv/bin/pylsp")
            try await eventually { recorder.manager.notifications.count == 1 }
            let notification = try #require(recorder.manager.notifications.first)

            notification.action()
            try await eventually { recorder.restarted == ["/ws"] }

            #expect(recorder.asked.map(\.path) == ["/ws"])
            #expect(trust.isTrusted(URL(fileURLWithPath: "/ws")))
        }
    }

    @Test
    func decliningTrustFromTheActionRestartsNothing() async throws {
        try await withIsolatedDefaults { defaults in
            let recorder = Recorder(answer: false)
            let (notifier, trust) = makeNotifier(recorder, defaults: defaults)
            notifier.announce(workspacePath: "/ws", executable: "/ws/venv/bin/pylsp")
            try await eventually { recorder.manager.notifications.count == 1 }
            let notification = try #require(recorder.manager.notifications.first)

            notification.action()
            try await eventually { recorder.asked.count == 1 }
            await lspServiceFlushMainQueue()

            #expect(recorder.restarted.isEmpty)
            #expect(!trust.isTrusted(URL(fileURLWithPath: "/ws")))
        }
    }

    @Test
    func anAlreadyTrustedWorkspaceRestartsWithoutAsking() async throws {
        try await withIsolatedDefaults { defaults in
            let recorder = Recorder(answer: false)
            let (notifier, trust) = makeNotifier(recorder, defaults: defaults)
            trust.trust(URL(fileURLWithPath: "/ws"))

            #expect(await notifier.trustAndRestart(workspacePath: "/ws"))

            #expect(recorder.asked.isEmpty)
            #expect(recorder.restarted == ["/ws"])
        }
    }

    @Test
    func theLiveNotifierUsesTheSharedServices() async throws {
        let live = SafeModeNotifier.live
        #expect(live.notifications() === NotificationManager.shared)
        #expect(live.trust() === WorkspaceTrust.shared)
        await live.restartServers("/dreamder-tests/no-such-workspace")

        let probe = "safe-mode-live-probe"
        UntrustedWorkspaceServerNotice().note(workspacePath: "/dreamder-tests/live", executable: "/x/\(probe)")
        try await eventually {
            NotificationManager.shared.notifications.contains { $0.description.contains(probe) }
        }
        for notification in NotificationManager.shared.notifications where notification.description.contains(probe) {
            NotificationManager.shared.dismissNotification(notification)
        }
    }
}
