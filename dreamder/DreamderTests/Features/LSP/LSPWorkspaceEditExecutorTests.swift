import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LSPWorkspaceEditExecutorTests {
    private func edit(_ start: (Int, Int), _ end: (Int, Int), _ text: String) -> TextEdit {
        LSPExecutorEdits.text(start, end, text)
    }

    @Test
    func textEditsAreWrittenToFilesThatAreNotOpen() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "a.txt", "one\ntwo")
            let workspaceEdit = WorkspaceEdit(
                changes: [file.absoluteString: [edit((1, 0), (1, 3), "2"), edit((0, 0), (0, 3), "1")]],
                documentChanges: nil
            )

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result == ApplyWorkspaceEditResult(applied: true))
            #expect(try String(contentsOf: file, encoding: .utf8) == "1\n2")
        }
    }

    @Test
    func openDocumentsAreEditedThroughTheInjectedEditorOnly() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "open.txt", "disk")
            let seen = LSPExecutorRecorder<String>()
            let executor = fixture.executor(edit: { requests in
                requests.forEach { seen.append("\($0.uri)#\($0.edits.count)") }
                return requests.map { _ in .handled }
            })
            let workspaceEdit = WorkspaceEdit(
                changes: [file.absoluteString: [edit((0, 0), (0, 4), "memory")]],
                documentChanges: nil
            )

            let result = await executor.apply(workspaceEdit)

            #expect(result.applied)
            #expect(seen.values == ["\(file.absoluteString)#1"])
            #expect(try String(contentsOf: file, encoding: .utf8) == "disk")
        }
    }

    @Test
    func openDocumentEditorFailuresAreReportedWithTheChangeIndex() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let executor = fixture.executor(edit: { requests in requests.map { _ in .failed(LSPExecutorFailure()) } })
            let workspaceEdit = WorkspaceEdit(
                changes: ["file:///nowhere": [edit((0, 0), (0, 0), "x")]],
                documentChanges: nil
            )

            let result = await executor.apply(workspaceEdit)

            #expect(result == ApplyWorkspaceEditResult(applied: false, failureReason: "refused", failedChange: 0))
        }
    }

    @Test
    func theFirstPerformFailureStopsTheEditAndNamesTheFailedChange() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let first = try fixture.makeFile(in: fixture.root, "first.txt", "a")
            let third = try fixture.makeFile(in: fixture.root, "third.txt", "c")
            let missing = fixture.root.appending(path: "missing.txt")
            let insert = [edit((0, 1), (0, 1), "!")]
            let workspaceEdit = WorkspaceEdit(changes: nil, documentChanges: [first, missing, third].map { url in
                WorkspaceEditDocumentChange.textDocumentEdit(TextDocumentEdit(
                    textDocument: VersionedTextDocumentIdentifier(uri: url.absoluteString, version: nil),
                    edits: insert
                ))
            })

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result.applied == false)
            #expect(result.failedChange == 1)
            #expect(result.failureReason == "The file does not exist: \(missing.absoluteString)")
            #expect(try String(contentsOf: first, encoding: .utf8) == "a!")
            #expect(try String(contentsOf: third, encoding: .utf8) == "c")
        }
    }

    @Test
    func overlappingTextEditsFailWithoutTouchingTheFile() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "a.txt", "abcdef")
            let workspaceEdit = WorkspaceEdit(
                changes: [file.absoluteString: [edit((0, 0), (0, 4), "x"), edit((0, 2), (0, 5), "y")]],
                documentChanges: nil
            )

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "Text edits overlap",
                failedChange: 0
            ))
            #expect(try String(contentsOf: file, encoding: .utf8) == "abcdef")
        }
    }

    @Test
    func nonFileUrisAreRejected() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let workspaceEdit = WorkspaceEdit(
                changes: ["untitled:Untitled-1": [edit((0, 0), (0, 0), "x")]],
                documentChanges: nil
            )

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result.applied == false)
            #expect(result.failureReason == "Unsupported document URI: untitled:Untitled-1")
        }
    }

    @Test
    func editsOutsideTheDocumentOrWithReversedRangesReportTheirReason() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "a.txt", "one")
            let uri = file.absoluteString
            let reversedRange = LSPRange(startPair: (0, 3), endPair: (0, 1))
            let outside = WorkspaceEdit(changes: [uri: [edit((5, 0), (5, 0), "x")]], documentChanges: nil)
            let reversed = WorkspaceEdit(
                changes: [uri: [TextEdit(range: reversedRange, newText: "x")]],
                documentChanges: nil
            )
            let executor = fixture.executor()

            #expect(await executor.apply(outside) == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "Line 5 is outside the document (1 lines)",
                failedChange: 0
            ))
            #expect(await executor.apply(reversed) == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "Range \(reversedRange) ends before it starts",
                failedChange: 0
            ))
            #expect(try String(contentsOf: file, encoding: .utf8) == "one")
        }
    }

    @Test
    func filesThatAreNotUTF8CannotBeEdited() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = fixture.root.appending(path: "binary.dat")
            let bytes = Data([0xFF, 0xFE, 0xFD])
            try bytes.write(to: file)
            let workspaceEdit = WorkspaceEdit(
                changes: [file.absoluteString: [edit((0, 0), (0, 0), "x")]],
                documentChanges: nil
            )

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "The file cannot be decoded as UTF-8: \(file.absoluteString)",
                failedChange: 0
            ))
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test
    func createThenEditInOneWorkspaceEditSeesTheNewFile() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = fixture.root.appending(path: "created.txt")
            let uri = file.absoluteString
            let workspaceEdit = try LSPExecutorEdits.decode("""
            {"documentChanges": [
              {"kind": "create", "uri": "\(uri)"},
              {"textDocument": {"uri": "\(uri)", "version": null},
               "edits": [{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}},
                          "newText": "hi"}]}
            ]}
            """)

            let result = await fixture.executor().apply(workspaceEdit)

            #expect(result.applied)
            #expect(try String(contentsOf: file, encoding: .utf8) == "hi")
        }
    }
}

@Suite
struct LSPWorkspaceEditPreflightTests {
    private let insertAtStart = #"""
    "edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"a"}]
    """#

    @Test
    func theOpenDocumentSeamReceivesEveryTextEditAtOnceBeforeAnyFileOperationRuns() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let first = try fixture.makeFile(in: fixture.root, "first.txt", "first")
            let second = try fixture.makeFile(in: fixture.root, "second.txt", "second")
            let created = fixture.root.appending(path: "created.txt")
            let batches = LSPExecutorRecorder<[LSPOpenDocumentEdit]>()
            let existedDuringSeam = LSPExecutorRecorder<Bool>()
            let executor = fixture.executor(edit: { requests in
                batches.append(requests)
                existedDuringSeam.append(FileManager.default.fileExists(atPath: created.path))
                return requests.map { _ in .handled }
            })
            let workspaceEdit = try LSPExecutorEdits.decode("""
            {"documentChanges":[
              {"kind":"create","uri":"\(created.absoluteString)"},
              {"textDocument":{"uri":"\(first.absoluteString)","version":3},\(insertAtStart)},
              {"textDocument":{"uri":"\(second.absoluteString)","version":null},\(insertAtStart)}]}
            """)
            let insert = LSPExecutorEdits.text((0, 0), (0, 0), "a")

            let result = await executor.apply(workspaceEdit)

            #expect(result.applied)
            #expect(batches.values == [[
                LSPOpenDocumentEdit(index: 1, uri: first.absoluteString, edits: [insert], version: 3),
                LSPOpenDocumentEdit(index: 2, uri: second.absoluteString, edits: [insert], version: nil)
            ]])
            #expect(existedDuringSeam.values == [false])
            #expect(FileManager.default.fileExists(atPath: created.path))
            #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        }
    }

    @Test
    func aFailedOutcomePerformsNothingAndNamesTheOffendingChange() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let first = try fixture.makeFile(in: fixture.root, "first.txt", "first")
            let second = try fixture.makeFile(in: fixture.root, "second.txt", "second")
            let created = fixture.root.appending(path: "created.txt")
            let executor = fixture.executor(edit: { requests in
                requests.map { $0.index == 2 ? .failed(LSPExecutorFailure()) : .notOpen }
            })
            let workspaceEdit = try LSPExecutorEdits.decode("""
            {"documentChanges":[
              {"kind":"create","uri":"\(created.absoluteString)"},
              {"textDocument":{"uri":"\(first.absoluteString)","version":null},\(insertAtStart)},
              {"textDocument":{"uri":"\(second.absoluteString)","version":null},\(insertAtStart)}]}
            """)

            let result = await executor.apply(workspaceEdit)

            #expect(result == ApplyWorkspaceEditResult(applied: false, failureReason: "refused", failedChange: 2))
            #expect(!FileManager.default.fileExists(atPath: created.path))
            #expect(try String(contentsOf: first, encoding: .utf8) == "first")
            #expect(try String(contentsOf: second, encoding: .utf8) == "second")
        }
    }

    @Test
    func onlyEditsTheSeamDidNotHandleFallBackToTheDisk() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let open = try fixture.makeFile(in: fixture.root, "open.txt", "open")
            let closed = try fixture.makeFile(in: fixture.root, "closed.txt", "closed")
            let executor = fixture.executor(edit: { requests in
                requests.map { $0.index == 0 ? .handled : .notOpen }
            })
            let workspaceEdit = try LSPExecutorEdits.decode("""
            {"documentChanges":[
              {"textDocument":{"uri":"\(open.absoluteString)","version":null},\(insertAtStart)},
              {"textDocument":{"uri":"\(closed.absoluteString)","version":null},\(insertAtStart)}]}
            """)

            let result = await executor.apply(workspaceEdit)

            #expect(result.applied)
            #expect(try String(contentsOf: open, encoding: .utf8) == "open")
            #expect(try String(contentsOf: closed, encoding: .utf8) == "aclosed")
        }
    }

    @Test
    func theValidationFailureTextsNameTheDocument() {
        #expect(
            LSPWorkspaceEditError.staleDocument("file:///a").errorDescription
                == "The document changed after the edit was computed: file:///a"
        )
        #expect(
            LSPWorkspaceEditError.unsyncedLocalEdits("file:///a").errorDescription
                == "The document has local edits the language server has not seen yet: file:///a"
        )
        #expect(
            LSPWorkspaceEditError.outsideWorkspace("file:///a").errorDescription
                == "The file is outside the workspace: file:///a"
        )
    }
}
