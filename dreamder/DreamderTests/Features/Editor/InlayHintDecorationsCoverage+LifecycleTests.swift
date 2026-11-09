import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class InlayHintConfigurationCalls {
    var invocationCount = 0
}

extension InlayHintDecorationsCoverageTests {
    func plainSession(in directory: URL) async throws -> DecorationsCoverageSession {
        try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
            [fixture.document.contentCoordinator]
        }
    }

    @Test
    func aSecondAppearanceRefreshesAgainWithoutDuplicatingTheHints() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [9] }

            coordinator.controllerDidAppear(controller: session.controller)
            try await eventually { connection.inlayRequestCount == 2 }
            try await Task.sleep(for: Self.settleDelay)

            #expect(connection.inlayRequestCount == 2)
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [9])
        }
    }

    @Test
    func scrollingBeforeAnyResponseHasBeenAppliedRequestsTheNewWindow() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(failsInlayRequests: true)
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            try await eventually { connection.inlayRequestCount == 1 }

            try scroll(session, toLine: 200)

            try await eventually { connection.inlayRequestCount >= 2 }
            let range = try #require(connection.inlayRanges.last)
            #expect(range.start.line == 200 - InlayHintCoordinator.visibleMarginLines)
        }
    }

    @Test
    func aPendingScrollRefreshIsSkippedWhenTheWindowIsCoveredByThen() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection()
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection, contents: Self.longSource)
            defer { harness.close() }
            let session = harness.session
            try await eventually { appliedBatches(notifications, in: session) == 1 }

            try scroll(session, toLine: 200)
            try scroll(session, toLine: 0)
            try await Task.sleep(for: Self.settleDelay)

            #expect(connection.inlayRequestCount == 1)
            #expect(appliedBatches(notifications, in: session) == 1)
        }
    }

    @Test
    func aCoordinatorWithoutAControllerNeverRequestsAndDestroysTwiceCleanly() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [9] }
            let detached = InlayHintCoordinator(
                codeFile: session.fixture.document,
                settings: isolatedSettings(in: directory)
            )

            detached.controllerDidAppear(controller: session.controller)
            try await Task.sleep(for: Self.settleDelay)
            #expect(connection.inlayRequestCount == 1)
            detached.destroy()

            coordinator.destroy()
            coordinator.destroy()
            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)
            #expect(connection.inlayRequestCount == 1)
        }
    }

    @Test
    func settingsChangesWithoutALanguageClientNeverPushTheServerConfiguration() async throws {
        try await withTempDir { directory in
            let session = try await plainSession(in: directory)
            defer { session.close() }
            let settings = isolatedSettings(in: directory)
            let calls = InlayHintConfigurationCalls()
            let coordinator = InlayHintCoordinator(
                codeFile: session.fixture.document,
                settings: settings,
                languageServerConfiguration: { _ in
                    calls.invocationCount += 1
                    return .hash([:])
                }
            )
            coordinator.prepareCoordinator(controller: session.controller)
            session.textView.layoutManager.attachments.add(
                InlayHintAttachment(text: ": Old", fontSize: 11),
                for: NSRange(location: 5, length: 0)
            )
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [5])

            settings.preferences.textEditing.inlayHints.enabled = false
            try await eventually { attachmentOffsets(in: session, inlayOnly: true).isEmpty }

            #expect(calls.invocationCount == 0)
            coordinator.destroy()
        }
    }

    @Test
    func aCoordinatorReleasedWhileItsSettingsObservationIsPendingLeavesTheEditorUntouched() async throws {
        try await withTempDir { directory in
            let session = try await plainSession(in: directory)
            defer { session.close() }
            let settings = isolatedSettings(in: directory)
            session.textView.layoutManager.attachments.add(
                InlayHintAttachment(text: ": Keep", fontSize: 11),
                for: NSRange(location: 5, length: 0)
            )

            var settled: InlayHintCoordinator? = InlayHintCoordinator(
                codeFile: session.fixture.document,
                settings: settings
            )
            settled?.prepareCoordinator(controller: session.controller)
            for _ in 0..<20 {
                await Task.yield()
            }
            settings.preferences.textEditing.inlayHints.parameterNames = .all
            settled = nil
            for _ in 0..<20 {
                await Task.yield()
            }

            var immediate: InlayHintCoordinator? = InlayHintCoordinator(
                codeFile: session.fixture.document,
                settings: settings
            )
            immediate?.prepareCoordinator(controller: session.controller)
            immediate = nil
            for _ in 0..<20 {
                await Task.yield()
            }

            #expect(settings.preferences.textEditing.inlayHints.parameterNames == .all)
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [5])
        }
    }
}
