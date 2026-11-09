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
private final class InlayHintCoverageNotificationLog {
    private(set) var objects: [ObjectIdentifier] = []
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let identifier = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated {
                if let identifier {
                    self?.objects.append(identifier)
                }
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}

private final class InlayHintCoverageOtherAttachment: TextAttachment {
    let width: CGFloat = 10
    var isSelected = false

    func draw(in context: CGContext, rect: NSRect) {}

    func attachmentAction() -> TextAttachmentAction {
        .none
    }
}

@MainActor
@Suite(.uiGate)
struct InlayHintDecorationsCoverageTests {
    private static let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3\nlet delta = 4\n"

    @MainActor
    private struct Harness {
        let session: DecorationsCoverageSession
        let connection: InlayHintDecorationsServerConnection
        let service: LSPService
        let key: LSPService.ClientKey

        func close() {
            session.close()
            service.languageClients[key] = nil
        }
    }

    private func hint(_ label: TwoTypeOption<String, [InlayHintLabelPart]>, line: Int, character: Int) -> InlayHint {
        InlayHint(position: Position(line: line, character: character), label: label, kind: .type)
    }

    private func makeServer(
        in directory: URL,
        connection: InlayHintDecorationsServerConnection,
        advertisesInlayHints: Bool
    ) async throws -> LSPService.LanguageServerType {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(
            TextDocumentSyncOptions(
                openClose: true,
                change: .incremental,
                willSave: true,
                willSaveWaitUntil: false,
                save: nil
            )
        )
        if advertisesInlayHints {
            capabilities.inlayHintProvider = .optionA(true)
        }
        let server = LSPService.LanguageServerType(
            languageId: .swift,
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(
                    workspacePath: directory.path()
                )
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: directory,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    private func openHarness(
        in directory: URL,
        connection: InlayHintDecorationsServerConnection,
        advertisesInlayHints: Bool = true,
        contents: String = InlayHintDecorationsCoverageTests.source,
        settings: Settings? = nil,
        languageServerConfiguration: (@MainActor (InlayHintSettings) -> LSPAny)? = nil
    ) async throws -> Harness {
        let settings = settings ?? Settings(baseURL: directory.appending(path: "settings", directoryHint: .isDirectory))
        let service = LSPService.shared
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let server = try await makeServer(in: directory, connection: connection, advertisesInlayHints: advertisesInlayHints)
        try await server.openDocument(fixture.document)
        let key = LSPService.ClientKey(.swift, directory.path() + "/")
        service.languageClients[key] = server
        let coordinator: InlayHintCoordinator
        if let languageServerConfiguration {
            coordinator = InlayHintCoordinator(
                codeFile: fixture.document,
                settings: settings,
                languageServerConfiguration: languageServerConfiguration
            )
        } else {
            coordinator = InlayHintCoordinator(codeFile: fixture.document, settings: settings)
        }
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        let fileURL = try #require(fixture.document.fileURL)
        let session = DecorationsCoverageSession(
            workspace: nil,
            fixture: fixture,
            hosted: hosted,
            controller: controller,
            textView: textView,
            fileURL: fileURL
        )
        return Harness(session: session, connection: connection, service: service, key: key)
    }

    private func attachmentOffsets(in session: DecorationsCoverageSession, inlayOnly: Bool) -> [Int] {
        let everything = NSRange(location: 0, length: session.textView.textStorage.length + 1)
        return session.textView.layoutManager.attachments.getAttachmentsStartingIn(everything)
            .filter { !inlayOnly || $0.attachment is InlayHintAttachment }
            .map(\.range.location)
            .sorted()
    }

    @Test
    func serverHintsBecomeAttachmentsAtTheirPositionsAndInvalidOnesAreSkipped() async throws {
        try await withTempDir { directory in
            let parts = [InlayHintLabelPart(value: ": "), InlayHintLabelPart(value: "String")]
            let connection = InlayHintDecorationsServerConnection(
                hints: [
                    hint(.optionA(": Int"), line: 0, character: 9),
                    hint(.optionB(parts), line: 1, character: 4),
                    hint(.optionA("   "), line: 2, character: 0),
                    hint(.optionA(": Gone"), line: 99, character: 0),
                    hint(.optionA(": Far"), line: 2, character: 999),
                    hint(.optionA(": Negative"), line: 2, character: -1),
                    hint(.optionA(": Start"), line: 3, character: 0)
                ]
            )
            let notifications = InlayHintCoverageNotificationLog(name: InlayHintCoordinator.hintsDidChangeNotification)
            defer { notifications.stop() }
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session

            let expected = [9, try session.lineStart(1) + 4, try session.lineStart(3)]
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == expected }

            try await eventually { notifications.objects.contains(ObjectIdentifier(session.textView)) }
            #expect(connection.inlayRequestCount >= 1)
            #expect(attachmentOffsets(in: session, inlayOnly: false) == expected)
        }
    }

    @Test
    func laterResponsesReplaceEarlierHintsAndKeepForeignAttachments() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [9] }
            session.textView.layoutManager.attachments.add(
                InlayHintCoverageOtherAttachment(),
                for: NSRange(location: 3, length: 0)
            )

            connection.setHints([hint(.optionA(": Bool"), line: 2, character: 3)])
            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "")
            let replaced = try session.lineStart(2) + 3
            try await eventually { attachmentOffsets(in: session, inlayOnly: true) == [replaced] }

            #expect(attachmentOffsets(in: session, inlayOnly: false) == [3, replaced])
        }
    }

    @Test
    func serverWithoutInlayHintCapabilityClearsExistingHintsWithoutRequesting() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(
                hints: [hint(.optionA(": Int"), line: 0, character: 9)]
            )
            let harness = try await openHarness(in: directory, connection: connection, advertisesInlayHints: false)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            let attachments = session.textView.layoutManager.attachments
            attachments.add(InlayHintAttachment(text: ": Old", fontSize: 11), for: NSRange(location: 5, length: 0))
            attachments.add(InlayHintCoverageOtherAttachment(), for: NSRange(location: 8, length: 0))

            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "")
            try await eventually { attachmentOffsets(in: session, inlayOnly: true).isEmpty }

            #expect(attachmentOffsets(in: session, inlayOnly: false) == [8])
            #expect(connection.inlayRequestCount == 0)
        }
    }

    @Test
    func failedInlayRequestLeavesTheCurrentHintsUntouched() async throws {
        try await withTempDir { directory in
            let connection = InlayHintDecorationsServerConnection(failsInlayRequests: true)
            let harness = try await openHarness(in: directory, connection: connection)
            defer { harness.close() }
            let session = harness.session
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            session.textView.layoutManager.attachments.add(
                InlayHintAttachment(text: ": Old", fontSize: 11),
                for: NSRange(location: 5, length: 0)
            )

            coordinator.textView(session.textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "")
            try await eventually { connection.inlayRequestCount >= 1 }
            try await Task.sleep(for: .milliseconds(150))

            #expect(attachmentOffsets(in: session, inlayOnly: true) == [5])
        }
    }

    @Test
    func attachmentPaintsARoundedPillAndHasNoClickAction() throws {
        let attachment = InlayHintAttachment(text: ": Int", fontSize: 12)
        let width = Int(ceil(attachment.width))
        let height = 24
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let rect = NSRect(x: 0, y: 4, width: CGFloat(width), height: 16)

        attachment.draw(in: context, rect: rect)

        let image = try #require(context.makeImage())
        let representation = NSBitmapImageRep(cgImage: image)
        let insidePill = representation.colorAt(x: Int(InlayHintAttachment.margin) + 1, y: height / 2)
        let outsidePill = representation.colorAt(x: 0, y: 0)
        #expect((insidePill?.alphaComponent ?? 0) > 0.3)
        #expect(outsidePill?.alphaComponent == 0)
        var isNone = false
        if case .none = attachment.attachmentAction() {
            isNone = true
        }
        #expect(isNone)
    }
}

extension InlayHintDecorationsCoverageTests {
    private static let longSource = (0..<400).map { "let value\($0) = \($0)\n" }.joined()
    private static let signatureSource = "func alpha() {}\nlet beta = alpha(1)\n"
    private static let settleDelay: Duration = .milliseconds(900)

    private func isolatedSettings(in directory: URL, _ mutate: (inout InlayHintSettings) -> Void = { _ in }) -> Settings {
        let settings = Settings(baseURL: directory.appending(path: "isolated-settings", directoryHint: .isDirectory))
        mutate(&settings.preferences.textEditing.inlayHints)
        return settings
    }

    private func expectedRange(in session: DecorationsCoverageSession) throws -> LSPRange {
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

    private func scroll(_ session: DecorationsCoverageSession, toLine line: Int) throws {
        let top = try #require(session.textView.layoutManager.textLineForIndex(line)).yPos
        let clipView = try #require(session.controller.scrollView).contentView
        clipView.scroll(to: NSPoint(x: 0, y: top))
        session.controller.scrollView.reflectScrolledClipView(clipView)
    }

    private func appliedBatches(_ log: InlayHintCoverageNotificationLog, in session: DecorationsCoverageSession) -> Int {
        let textView = ObjectIdentifier(session.textView)
        return log.objects.filter { $0 == textView }.count
    }

    private func postRefreshRequest(kind: String, path: String, from harness: Harness) {
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

            postRefreshRequest(kind: LSPRefreshKind.semanticTokens.rawValue, path: harness.key.workspacePath, from: harness)
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
