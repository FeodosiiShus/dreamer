import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class FormatOnSaveProbe {
    var formattedDocuments: [CodeFileDocument] = []
    var sawCancellation = false
}

@MainActor
@Suite("FormatOnSave", .uiGate)
struct FormattingFormatOnSaveTests {
    struct Scenario: CustomTestStringConvertible, Sendable {
        let name: String
        let enabled: Bool
        let hasFormatter: Bool
        let expectedFormats: Int

        var testDescription: String { name }
    }

    nonisolated static let scenarios: [Scenario] = [
        Scenario(name: "setting off", enabled: false, hasFormatter: true, expectedFormats: 0),
        Scenario(name: "no formatter applies", enabled: true, hasFormatter: false, expectedFormats: 0),
        Scenario(name: "setting off and no formatter", enabled: false, hasFormatter: false, expectedFormats: 0),
        Scenario(name: "formatter applies", enabled: true, hasFormatter: true, expectedFormats: 1)
    ]

    private func makeFormatOnSave(
        _ scenario: Scenario,
        probe: FormatOnSaveProbe,
        timeout: Duration = .seconds(5)
    ) -> FormatOnSave {
        FormatOnSave(
            isEnabled: { scenario.enabled },
            canFormat: { _ in scenario.hasFormatter },
            format: { probe.formattedDocuments.append($0) },
            timeout: timeout
        )
    }

    @Test(arguments: scenarios)
    func formatsTheWholeFileOnlyWhenTheSettingIsOnAndAFormatterApplies(_ scenario: Scenario) async {
        let probe = FormatOnSaveProbe()
        let formatOnSave = makeFormatOnSave(scenario, probe: probe)
        let document = CodeFileDocument()

        let shouldFormat = formatOnSave.shouldFormat(document)
        await formatOnSave.run(for: document)

        #expect(shouldFormat == (scenario.expectedFormats == 1))
        #expect(probe.formattedDocuments.count == scenario.expectedFormats)
        #expect(probe.formattedDocuments.allSatisfy { $0 === document })
    }

    @Test
    func aSlowFormatNeverBlocksTheSaveBeyondTheTimeoutAndIsCancelled() async throws {
        let probe = FormatOnSaveProbe()
        let formatOnSave = FormatOnSave(
            isEnabled: { true },
            canFormat: { _ in true },
            format: { _ in
                try? await Task.sleep(for: .seconds(30))
                probe.sawCancellation = Task.isCancelled
            },
            timeout: .milliseconds(50)
        )
        let clock = ContinuousClock()

        let elapsed = await clock.measure { await formatOnSave.run(for: CodeFileDocument()) }

        #expect(elapsed < .seconds(10))
        try await eventually { probe.sawCancellation }
    }

    @Test
    func aFormatThatFinishesQuicklyDoesNotWaitForTheTimeout() async throws {
        let formatOnSave = FormatOnSave(
            isEnabled: { true },
            canFormat: { _ in true },
            format: { _ in },
            timeout: .seconds(60)
        )
        let clock = ContinuousClock()

        let elapsed = await clock.measure { await formatOnSave.run(for: CodeFileDocument()) }

        #expect(elapsed < .seconds(30))
    }

    @Test
    func theLiveHelperReadsTheSettingAndFormatsThroughTheService() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])
            let store = Dreamder.Settings(baseURL: directory.appending(path: "settings", directoryHint: .isDirectory))
            var formatOnSave = FormatOnSave.live(
                service: harness.formattingService(),
                timeout: .seconds(5),
                settings: store
            )

            #expect(!formatOnSave.isEnabled())
            store.preferences.textEditing.formatOnSave = true
            #expect(formatOnSave.isEnabled())
            #expect(formatOnSave.canFormat(harness.document))
            formatOnSave.isEnabled = { true }
            await formatOnSave.run(for: harness.document)

            #expect(harness.text == "let x = 1\n")
            #expect(harness.connection.formattingParams.count == 1)
            #expect(FormatOnSave.defaultTimeout == .seconds(5))
        }
    }

    @Test
    func theLiveHelperSkipsDocumentsWithoutAFormatter() async throws {
        let service = FormattingService(lspService: { nil }, fileExists: { _ in false }, workspaceRoot: { _ in nil })
        var formatOnSave = FormatOnSave.live(service: service)
        formatOnSave.isEnabled = { true }

        #expect(!formatOnSave.shouldFormat(CodeFileDocument()))
        await formatOnSave.run(for: CodeFileDocument())
    }
}
