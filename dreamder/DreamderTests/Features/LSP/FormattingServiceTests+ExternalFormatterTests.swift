import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension FormattingServiceTests {
    @Test
    func prettierInTheWorkspaceIsPreferredOverTheServerAndItsOutputBecomesAMinimalUndoableEdit() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(
                runner: runner,
                existing: [harness.binaryPath("prettier")],
                environment: ["PATH": "/opt/node/bin"]
            )
            harness.select(NSRange(location: 3, length: 0))

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(harness.text == "let x = 1;\n")
            let invocation = try #require(runner.invocations.first)
            #expect(runner.invocations.count == 1)
            #expect(invocation.executable.path(percentEncoded: false) == harness.binaryPath("prettier"))
            let filePath = try #require(harness.document.fileURL).path(percentEncoded: false)
            #expect(invocation.arguments == ["--stdin-filepath", filePath])
            #expect(invocation.workingDirectory == harness.directory)
            #expect(invocation.standardInput == Data("let  x=1\n".utf8))
            #expect(invocation.environment == ["PATH": "/opt/node/bin"])
            #expect(invocation.timeout == Duration.seconds(30))
            #expect(harness.connection.formattingParams.isEmpty)
            #expect(harness.connection.rangeFormattingParams.isEmpty)

            harness.textView.undoManager?.undo()

            #expect(harness.text == "let  x=1\n")
        }
    }

    @Test
    func prettierReceivesTheSelectionAsUTF16RangeFlags() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("prettier")])
            harness.select(NSRange(location: 4, length: 3))

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            let arguments = try #require(runner.invocations.first).arguments
            #expect(Array(arguments.suffix(4)) == ["--range-start", "4", "--range-end", "7"])
        }
    }

    @Test
    func aFailingExternalFormatterLeavesTheTextUntouchedAndReportsStderr() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let recorder = FormattingRecorder()
            let runner = FakeProcessRunner { _ in
                FakeProcessRunner.output("garbage", stderr: "bad syntax\n", exitCode: 2)
            }
            let service = harness.formattingService(
                runner: runner,
                existing: [harness.binaryPath("prettier")],
                recorder: recorder
            )

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .failed)
            #expect(harness.text == "let  x=1\n")
            #expect(recorder.failures == ["bad syntax"])
            #expect(harness.connection.formattingParams.isEmpty)
        }
    }

    @Test
    func biomeCannotFormatASelectionSoTheServerRangeFormatterIsUsed() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("never used") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("biome")])
            harness.select(NSRange(location: 4, length: 3))
            try harness.scriptFormatting(.textDocumentRangeFormatting, edits: [harness.spacesEdit()])

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(runner.invocations.isEmpty)
            #expect(harness.connection.rangeFormattingParams.count == 1)
        }
    }

    @Test
    func biomeFormatsTheWholeFileThroughStdin() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("biome")])

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .applied)
            let filePath = try #require(harness.document.fileURL).path(percentEncoded: false)
            #expect(try #require(runner.invocations.first).arguments == ["format", "--stdin-file-path=\(filePath)"])
        }
    }

    @Test
    func projectFormattersNeverRunInAnUntrustedWorkspace() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("never used") }
            let service = harness.formattingService(
                runner: runner,
                existing: [harness.binaryPath("prettier"), harness.binaryPath("biome")],
                trusted: false
            )
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .applied)
            #expect(runner.invocations.isEmpty)
            #expect(harness.connection.formattingParams.count == 1)
        }
    }
}
