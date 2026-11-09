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
final class InlayHintCoverageNotificationLog {
    private(set) var objects: [ObjectIdentifier] = []
    var token: NSObjectProtocol?

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
    static let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3\nlet delta = 4\n"

    @MainActor
    struct Harness {
        let session: DecorationsCoverageSession
        let connection: InlayHintDecorationsServerConnection
        let service: LSPService
        let key: LSPService.ClientKey

        func close() {
            session.close()
            service.languageClients[key] = nil
        }
    }

    func hint(_ label: TwoTypeOption<String, [InlayHintLabelPart]>, line: Int, character: Int) -> InlayHint {
        InlayHint(position: Position(line: line, character: character), label: label, kind: .type)
    }

    func makeServer(
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

    func openHarness(
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
        let server = try await makeServer(
            in: directory,
            connection: connection,
            advertisesInlayHints: advertisesInlayHints
        )
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

    func attachmentOffsets(in session: DecorationsCoverageSession, inlayOnly: Bool) -> [Int] {
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
