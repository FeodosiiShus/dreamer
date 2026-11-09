import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension InlayHintDecorationsCoverageTests {
    static let longSource = (0..<400).map { "let value\($0) = \($0)\n" }.joined()
    static let signatureSource = "func alpha() {}\nlet beta = alpha(1)\n"
    static let settleDelay: Duration = .milliseconds(900)

    func isolatedSettings(in directory: URL, _ mutate: (inout InlayHintSettings) -> Void = { _ in }) -> Settings {
        let settings = Settings(baseURL: directory.appending(path: "isolated-settings", directoryHint: .isDirectory))
        mutate(&settings.preferences.textEditing.inlayHints)
        return settings
    }

    func expectedRange(in session: DecorationsCoverageSession) throws -> LSPRange {
        let layoutManager = try #require(session.textView.layoutManager)
        let visible = session.textView.visibleRect
        let first = try #require(layoutManager.textLineForPosition(max(visible.minY, 0))).index
        let last = max(layoutManager.textLineForPosition(visible.maxY)?.index ?? layoutManager.lineCount - 1, first)
        return LSPRange(
            start: Position(line: max(first - InlayHintCoordinator.visibleMarginLines, 0), character: 0),
            end: Position(
                line: min(last + InlayHintCoordinator.visibleMarginLines + 1, layoutManager.lineCount),
                character: 0
            )
        )
    }

    func scroll(_ session: DecorationsCoverageSession, toLine line: Int) throws {
        let top = try #require(session.textView.layoutManager.textLineForIndex(line)).yPos
        let clipView = try #require(session.controller.scrollView).contentView
        clipView.scroll(to: NSPoint(x: 0, y: top))
        session.controller.scrollView.reflectScrolledClipView(clipView)
    }

    func appliedBatches(_ log: InlayHintCoverageNotificationLog, in session: DecorationsCoverageSession) -> Int {
        let textView = ObjectIdentifier(session.textView)
        return log.objects.filter { $0 == textView }.count
    }

    func postRefreshRequest(kind: String, path: String, from harness: Harness) {
        NotificationCenter.default.post(
            name: LSPService.refreshRequestedNotification,
            object: harness.service,
            userInfo: [
                LSPService.refreshKindUserInfoKey: kind,
                LSPService.refreshWorkspacePathUserInfoKey: path
            ]
        )
    }

    @Test
    func requestCoversTheVisibleLinesPlusTheMargin() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            try await eventually { connection.inlayRanges.count == 1 }

            let range = connection.inlayRanges[0]
            #expect(range.start == Position(line: 0, character: 0))
            #expect(range == (try expectedRange(in: harness.session)))
            #expect(range.end.line > InlayHintCoordinator.visibleMarginLines)
            #expect(range.end.line < 400)
        }
    }

    @Test
    func scrollingInsideTheCoveredRangeDoesNotRefetchButScrollingFarAwayRequestsOnlyTheNewWindow() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            try await eventually { appliedBatches(notifications, in: session) == 1 }

            try scroll(session, toLine: 10)
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 1)

            try scroll(session, toLine: 200)
            try await eventually { appliedBatches(notifications, in: session) == 2 }
            let range = try #require(connection.inlayRanges.last)
            #expect(range.start.line == 200 - InlayHintCoordinator.visibleMarginLines)
            #expect(range == (try expectedRange(in: session)))
            #expect(range.end.line < 400)
        }
    }

    @Test
    func hintsOutsideTheRequestedWindowSurviveAReplacement() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Near"), line: 1, character: 5)]
            )
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            let near = try session.lineStart(1) + 5
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [near] }

            connection.setHints([hint(.optionA(": Far"), line: 250, character: 3)])
            try scroll(session, toLine: 250)
            let far = try session.lineStart(250) + 3
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [near, far] }
        }
    }

    @Test
    func editsOutsideTheRequestedRangeDoNotRefetchAndEditsInsideDo() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { appliedBatches(notifications, in: session) == 1 }

            let far = try session.lineStart(300)
            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: far, length: 0), with: "x")
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 1)

            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 4, length: 0), with: "x")
            try await eventually { appliedBatches(notifications, in: session) == 2 }
            #expect(connection.inlayRanges.first == connection.inlayRanges.last)
        }
    }

    @Test
    func editsBeforeTheRequestedRangeShiftItWithoutRefetching() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { appliedBatches(notifications, in: session) == 1 }
            try scroll(session, toLine: 250)
            try await eventually { appliedBatches(notifications, in: session) == 2 }

            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 3, length: 0), with: "abc")
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 2)
        }
    }

    @Test
    func editsWhileARequestIsInFlightAlwaysRefetch() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            connection.setInlayDelay(.milliseconds(500))
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { connection.inlayRanges.count == 1 }

            let far = try session.lineStart(300)
            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: far, length: 0), with: "x")
            try await eventually { connection.inlayRanges.count == 2 }
        }
    }

    @Test
    func serverRefreshRequestsDropTheCachedHintsAndRefetchOnlyForInlayHintsOfThisWorkspace() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Old"), line: 0, character: 9)]
            )
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { appliedBatches(notifications, in: session) == 1 }
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [9])

            postRefreshRequest(
                kind: LSPRefreshKind.semanticTokens.rawValue,
                path: harness.key.workspacePath,
                from: harness
            )
            postRefreshRequest(kind: LSPRefreshKind.inlayHint.rawValue, path: "/elsewhere/", from: harness)
            NotificationCenter.default.post(name: LSPService.refreshRequestedNotification, object: harness.service)

            connection.setHints([hint(.optionA(": New"), line: 1, character: 5)])
            postRefreshRequest(kind: LSPRefreshKind.inlayHint.rawValue, path: harness.key.workspacePath, from: harness)
            try await eventually { appliedBatches(notifications, in: session) == 2 }

            let replaced = try session.lineStart(1) + 5
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [replaced])
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 2)

            coordinator.destroy()
            postRefreshRequest(kind: LSPRefreshKind.inlayHint.rawValue, path: harness.key.workspacePath, from: harness)
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 2)
        }
    }

    @Test
    func disabledSettingSendsNoRequestAndRemovesHintsLive() async throws {
        try await withTempDir { directory in
            let settings = isolatedSettings(in: directory) { $0.enabled = false }
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection, settings: settings)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            session.textView.layoutManager.attachments.add(
                InlayHintAttachment(text: ": Old", fontSize: 11),
                for: NSRange(location: 5, length: 0)
            )

            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "")
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 0)
            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)

            settings.preferences.textEditing.inlayHints.enabled = true
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [9] }
            #expect(connection.inlayRequestCount >= 1)

            settings.preferences.textEditing.inlayHints.enabled = false
            try await eventually { attachmentOffsets(in: session, inlayOnly: true).isEmpty }
            let requests = connection.inlayRequestCount
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == requests)
        }
    }

    @Test
    func disablingWhileTheRefreshIsPendingRemovesHintsWithoutRequesting() async throws {
        try await withTempDir { directory in
            let settings = isolatedSettings(in: directory)
            let connection = InlayHintDecorationsServerConnection(failsInlayRequests: true)
            let harness = try await openHarness(in: directory, connection: connection, settings: settings)
            defer { harness.close() }
            let session = harness.session
            try await eventually { connection.inlayRequestCount >= 1 }
            settings.preferences.textEditing.inlayHints.enabled = false
            try await Task.sleep(for: .milliseconds(300))
            let requests = connection.inlayRequestCount
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == requests)
            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)
        }
    }

    @Test
    func perKindTogglesFilterParameterTypeAndReturnTypeHints() async throws {
        try await withTempDir { directory in
            let settings = isolatedSettings(in: directory)
            let connection = InlayHintDecorationsServerConnection(
                hints: [
                    InlayHint(position: Position(line: 0, character: 12), label: .optionA(": Void"), kind: .type),
                    InlayHint(position: Position(line: 1, character: 8), label: .optionA(": Int"), kind: .type),
                    InlayHint(position: Position(line: 1, character: 17), label: .optionA("x:"), kind: .parameter),
                    InlayHint(position: Position(line: 1, character: 0), label: .optionA("§"), kind: nil)
                ]
            )
            let harness = try await openHarness(
                in: directory,
                connection: connection,
                contents: Self.signatureSource,
                settings: settings
            )
            defer { harness.close() }
            let session = harness.session
            let returnType = 12
            let variable = try session.lineStart(1) + 8
            let parameter = try session.lineStart(1) + 17
            let untyped = try session.lineStart(1)
            try await eventually {
                attachmentOffsets(in: session, inlayOnly: true) == [returnType, untyped, variable, parameter]
            }

            settings.preferences.textEditing.inlayHints.types = false
            try await eventually {
                attachmentOffsets(in: session, inlayOnly: true) == [returnType, untyped, parameter]
            }

            settings.preferences.textEditing.inlayHints.returnTypes = false
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [untyped, parameter] }

            settings.preferences.textEditing.inlayHints.parameterNames = .none
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [untyped] }
        }
    }

    @Test
    func changingSettingsPushesTheConfigurationToTheServer() async throws {
        try await withTempDir { directory in
            let settings = isolatedSettings(in: directory)
            let connection = InlayHintDecorationsServerConnection()
            let harness = try await openHarness(
                in: directory,
                connection: connection,
                settings: settings,
                languageServerConfiguration: { .hash(["parameterNames": .string($0.parameterNames.rawValue)]) }
            )
            defer { harness.close() }
            try await eventually { connection.inlayRequestCount >= 1 }

            settings.preferences.textEditing.inlayHints.parameterNames = .all
            try await eventually { connection.configurationSettings.count == 1 }
            #expect(connection.configurationSettings == [.hash(["parameterNames": .string("all")])])
        }
    }

    @Test
    func changingSettingsPushesTheDefaultServerPreferencesWhenNoConfigurationIsInjected() async throws {
        try await withTempDir { directory in
            let settings = isolatedSettings(in: directory)
            let connection = InlayHintDecorationsServerConnection()
            let harness = try await openHarness(in: directory, connection: connection, settings: settings)
            defer { harness.close() }
            try await eventually { connection.inlayRequestCount >= 1 }

            settings.preferences.textEditing.inlayHints.parameterNames = .all
            try await eventually { connection.configurationSettings.count == 1 }

            #expect(connection.configurationSettings == [
                InlayHintServerPreferences.configurationSettings(for: settings.preferences.textEditing.inlayHints)
            ])
        }
    }

    @Test
    func scrollObservationAndSettingsObservationEndWithTheCoordinator() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [9] }

            coordinator.destroy()
            try scroll(session, toLine: 300)
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 1)
            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)
        }
    }
}
