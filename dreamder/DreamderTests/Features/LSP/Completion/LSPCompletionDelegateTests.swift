import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LSPCompletionDelegateTests {
    typealias Delegate = LSPCompletionDelegate<SyncTestDocument>

    @MainActor
    struct Fixture {
        let harness: SyncTestServer
        let delegate: Delegate
        let hosted: HostedSourceEditor
        let controller: TextViewController
        let textView: TextView

        var text: String {
            textView.string
        }

        var selection: NSRange {
            textView.selectionManager.textSelections.first?.range ?? NSRange(location: NSNotFound, length: 0)
        }

        var connection: ScriptedServerConnection {
            harness.connection
        }

        func place(_ caret: Int) {
            controller.setCursorPositions([CursorPosition(range: NSRange(location: caret, length: 0))])
        }

        func position(at offset: Int) throws -> CursorPosition {
            try #require(controller.resolveCursorPosition(CursorPosition(range: NSRange(location: offset, length: 0))))
        }

        func request(at caret: Int) async throws -> [LSPCompletionSuggestion] {
            place(caret)
            let result = await delegate.completionSuggestionsRequested(
                textView: controller,
                cursorPosition: try position(at: caret)
            )
            return (result?.items ?? []).compactMap { $0 as? LSPCompletionSuggestion }
        }

        func moved(to caret: Int) throws -> [LSPCompletionSuggestion]? {
            place(caret)
            return delegate
                .completionOnCursorMove(textView: controller, cursorPosition: try position(at: caret))?
                .compactMap { $0 as? LSPCompletionSuggestion }
        }

        func apply(_ suggestion: LSPCompletionSuggestion, cursorPosition: CursorPosition? = nil) {
            delegate.completionWindowApplyCompletion(
                item: suggestion,
                textView: controller,
                cursorPosition: cursorPosition
            )
        }

        func focus() throws {
            try #require(hosted.window.makeFirstResponder(textView))
            try #require(hosted.window.firstResponder === textView)
        }

        func tab(shift: Bool = false) throws -> NSEvent {
            try focus()
            return try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: shift ? .shift : [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: hosted.window.windowNumber,
                    context: nil,
                    characters: "\t",
                    charactersIgnoringModifiers: "\t",
                    isARepeat: false,
                    keyCode: 48
                )
            )
        }

        func close() {
            delegate.reset()
            hosted.close()
        }
    }

    private func capabilities(
        resolve: Bool = false,
        commit: [String]? = nil,
        triggers: [String]? = nil
    ) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.completionProvider = CompletionOptions(
            workDoneProgress: false,
            triggerCharacters: triggers,
            allCommitCharacters: commit,
            resolveProvider: resolve,
            completionItem: nil
        )
        return capabilities
    }

    private func list(incomplete: Bool = false, _ items: [String]) -> String {
        #"{"isIncomplete":\#(incomplete),"items":[\#(items.joined(separator: ","))]}"#
    }

    private func item(_ label: String, extra: String = "") -> String {
        #"{"label":"\#(label)"\#(extra)}"#
    }

    private func edit(_ line: Int, _ start: Int, _ end: Int, _ text: String) -> String {
        let range = #"{"start":{"line":\#(line),"character":\#(start)},"end":{"line":\#(line),"character":\#(end)}}"#
        return #"{"range":\#(range),"newText":"\#(text)"}"#
    }

    private func makeFixture(
        in directory: URL,
        text: String,
        completion: String? = nil,
        capabilities: ServerCapabilities? = nil,
        harness customHarness: SyncTestServer? = nil
    ) async throws -> Fixture {
        let harness: SyncTestServer
        if let customHarness {
            harness = customHarness
        } else {
            harness = try await SyncTestServer.make(capabilities: capabilities ?? self.capabilities())
        }
        let document = try await harness.open(text: text)
        if let completion {
            try harness.connection.script(
                .textDocumentCompletion,
                SyncTestServer.decode(CompletionList.self, completion)
            )
        }
        let delegate = Delegate()
        delegate.setUp(server: harness.server, document: document)
        let editor = try HostedSourceEditorFixture.make(in: directory, contents: text)
        let hosted = editor.host(coordinators: [], size: NSSize(width: 900, height: 600))
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        try await eventually {
            hosted.window.makeFirstResponder(textView) && hosted.window.firstResponder === textView
        }
        return Fixture(harness: harness, delegate: delegate, hosted: hosted, controller: controller, textView: textView)
    }

    @Test func triggerCharactersFollowTheServerCapabilities() async throws {
        let unset = Delegate()
        #expect(unset.completionTriggerCharacters().isEmpty)

        let withoutProvider = try await SyncTestServer.make()
        let document = try await withoutProvider.open()
        unset.setUp(server: withoutProvider.server, document: document)
        #expect(unset.completionTriggerCharacters().isEmpty)

        let defaults = try await SyncTestServer.make(capabilities: capabilities())
        unset.setUp(server: defaults.server, document: document)
        #expect(unset.completionTriggerCharacters() == [".", "\"", "(", "[", "<", "/", "'"])

        let explicit = try await SyncTestServer.make(capabilities: capabilities(triggers: [":", "."]))
        unset.setUp(server: explicit.server, document: document)
        #expect(unset.completionTriggerCharacters() == [":", "."])
    }

    @Test func requestsRankByMatchingDegreeAndFilterByThePrefix() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = pr",
                completion: list([item("print"), item("precondition"), item("zeta"), item("printf")])
            )
            defer { fixture.close() }
            let items = try await fixture.request(at: 10)
            #expect(items.map(\.label) == ["precondition", "print", "printf"])
            #expect(fixture.connection.requestCount(.textDocumentCompletion) == 1)
        }
    }

    @Test func requestsHonourTheItemRangeWhenFiltering() async throws {
        try await withTempDir { directory in
            let range = edit(0, 4, 6, "bar")
            let elsewhere = edit(9, 0, 1, "x")
            let items = [
                item("bar", extra: #","textEdit":\#(range)"#),
                item("baz", extra: #","textEdit":\#(range)"#),
                item("zzz", extra: #","textEdit":\#(range)"#),
                item("bar2"),
                item("elsewhere", extra: #","textEdit":\#(elsewhere)"#)
            ]
            let fixture = try await makeFixture(in: directory, text: "foo.ba", completion: list(items))
            defer { fixture.close() }
            let result = try await fixture.request(at: 6)
            #expect(result.map(\.label) == ["bar", "bar2", "baz"])
        }
    }

    @Test func aPrefixStartingOnAnEarlierLineFallsBackToTheIdentifierPrefix() async throws {
        try await withTempDir { directory in
            let crossLine = edit(0, 0, 2, "foo")
            let fixture = try await makeFixture(
                in: directory,
                text: "abc\nfo",
                completion: list([item("foo", extra: #","textEdit":\#(crossLine)"#), item("nope")])
            )
            defer { fixture.close() }
            let result = try await fixture.request(at: 6)
            #expect(result.map(\.label) == ["foo"])
        }
    }

    @Test func aPreselectedItemIsOfferedFirst() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = ",
                completion: list([item("a"), item("b", extra: #","preselect":true"#)])
            )
            defer { fixture.close() }
            let result = try await fixture.request(at: 4)
            #expect(result.map(\.label) == ["b", "a"])
        }
    }

    @Test func emptyAndFailingResponsesOfferNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = ")
            defer { fixture.close() }
            #expect(try await fixture.request(at: 4).isEmpty)
            #expect(try fixture.moved(to: 4) == nil)
        }
        try await withTempDir { directory in
            let scripted = ScriptedServerConnection(capabilities: capabilities())
            let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentCompletion])
            let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities())
            let harness = SyncTestServer(connection: scripted, server: server)
            let fixture = try await makeFixture(in: directory, text: "x = ", harness: harness)
            defer { fixture.close() }
            #expect(try await fixture.request(at: 4).isEmpty)
        }
    }

    @Test func requestsWithoutAServerOfferNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = ")
            defer { fixture.close() }
            fixture.delegate.reset()
            #expect(try await fixture.request(at: 4).isEmpty)
        }
    }

    @Test func additionalEditsAreAppliedTogetherWithTheMainEditAndUndoRevertsBoth() async throws {
        try await withTempDir { directory in
            let importEdit = edit(0, 0, 0, #"import Foo\n"#)
            let mainEdit = edit(0, 8, 10, "foo")
            let extra = #","textEdit":\#(mainEdit),"additionalTextEdits":[\#(importEdit)]"#
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let items = try await fixture.request(at: 10)
            let suggestion = try #require(items.first)
            fixture.apply(suggestion)
            #expect(fixture.text == "import Foo\nlet x = foo\n")
            #expect(fixture.selection == NSRange(location: 22, length: 0))

            fixture.textView.undoManager?.undo()
            #expect(fixture.text == "let x = fo\n")
        }
    }

    @Test func charactersTypedAfterTheRequestAreReplacedToo() async throws {
        try await withTempDir { directory in
            let extra = #","textEdit":\#(edit(0, 8, 10, "foo"))"#
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let suggestion = try #require(try await fixture.request(at: 10).first)
            fixture.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "o")
            fixture.place(11)
            fixture.apply(suggestion, cursorPosition: try fixture.position(at: 11))
            #expect(fixture.text == "let x = foo\n")
        }
    }

    @Test func invalidRangesAndOffsetsLeaveTheDocumentAlone() async throws {
        try await withTempDir { directory in
            let invalid = #","textEdit":\#(edit(9, 0, 1, "foo"))"#
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo", extra: invalid), item("fox")])
            )
            defer { fixture.close() }
            let items = try await fixture.request(at: 10)
            fixture.apply(try #require(items.first { $0.label == "foo" }))
            #expect(fixture.text == "let x = fo\n")
            fixture.apply(
                try #require(items.first { $0.label == "fox" }),
                cursorPosition: CursorPosition(range: NSRange(location: 999, length: 0))
            )
            #expect(fixture.text == "let x = fo\n")
        }
    }

    @Test func foreignItemsAreIgnored() async throws {
        struct Foreign: CodeSuggestionEntry {
            var label: String { "foreign" }
            var detail: String? { nil }
            var documentation: String? { nil }
            var pathComponents: [String]? { nil }
            var targetPosition: CursorPosition? { nil }
            var sourcePreview: String? { nil }
            var image: Image { Image("nodes/word") }
            var imageColor: SwiftUI.Color { .clear }
            var deprecated: Bool { false }
        }
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = ")
            defer { fixture.close() }
            fixture.delegate.completionWindowDidSelect(item: Foreign())
            fixture.delegate.completionWindowApplyCompletion(
                item: Foreign(),
                textView: fixture.controller,
                cursorPosition: nil
            )
            #expect(fixture.text == "x = ")
            #expect(fixture.connection.requestCount(.completionItemResolve) == 0)
        }
    }

    @Test func resolveIsRequestedOncePerSelectionAndItsEditsAreApplied() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo"), item("fob")]),
                capabilities: capabilities(resolve: true)
            )
            defer { fixture.close() }
            let resolved = CompletionItem(
                label: "foo",
                detail: "resolved detail",
                documentation: .optionA("resolved docs"),
                additionalTextEdits: [TextEdit(range: LSPRange.zero, newText: "import Foo\n")]
            )
            try fixture.connection.script(.completionItemResolve, resolved)
            let items = try await fixture.request(at: 10)
            let foo = try #require(items.first { $0.label == "foo" })
            let fob = try #require(items.first { $0.label == "fob" })

            fixture.delegate.completionWindowDidSelect(item: foo)
            fixture.delegate.completionWindowDidSelect(item: foo)
            try await eventually { foo.state.isResolved }
            fixture.delegate.completionWindowDidSelect(item: foo)
            for _ in 0..<5 { await Task.yield() }
            #expect(fixture.connection.requestCount(.completionItemResolve) == 1)
            #expect(foo.detail == "resolved detail")
            #expect(foo.documentation == "resolved docs")

            fixture.delegate.completionWindowDidSelect(item: fob)
            try await eventually { fob.state.isResolved }
            #expect(fixture.connection.requestCount(.completionItemResolve) == 2)

            fixture.apply(foo)
            #expect(fixture.text == "import Foo\nlet x = foo\n")
        }
    }

    @Test func applyingBeforeTheResolutionFinishedWaitsForIt() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo")]),
                capabilities: capabilities(resolve: true)
            )
            defer { fixture.close() }
            let resolved = CompletionItem(
                label: "foo",
                additionalTextEdits: [TextEdit(range: LSPRange.zero, newText: "import Foo\n")]
            )
            try fixture.connection.script(.completionItemResolve, resolved)
            let foo = try #require(try await fixture.request(at: 10).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            fixture.apply(foo)
            try await eventually { fixture.text == "import Foo\nlet x = foo\n" }
            #expect(fixture.connection.requestCount(.completionItemResolve) == 1)
        }
    }

    @Test func aCaretThatVanishesDuringTheResolutionFallsBackToTheRequestedOne() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo")]),
                capabilities: capabilities(resolve: true)
            )
            defer { fixture.close() }
            let resolved = CompletionItem(
                label: "foo",
                additionalTextEdits: [TextEdit(range: LSPRange.zero, newText: "import Foo\n")]
            )
            try fixture.connection.script(.completionItemResolve, resolved)
            let foo = try #require(try await fixture.request(at: 10).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            fixture.apply(foo)
            fixture.textView.selectionManager.setSelectedRanges([])

            try await eventually { fixture.text == "import Foo\nlet x = foo\n" }
        }
    }

    @Test func aCaretThatVanishesDuringTheRequestFallsBackToTheRequestedOffset() async throws {
        try await withTempDir { directory in
            let gate = LSPServiceGate()
            let caps = capabilities()
            let scripted = ScriptedServerConnection(capabilities: caps)
            let gated = GatedRequestConnection(inner: scripted, gatedMethods: [.textDocumentCompletion], gate: gate)
            let server = try await SyncTestServer.makeServer(connection: gated, capabilities: caps)
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo")]),
                harness: SyncTestServer(connection: scripted, server: server)
            )
            defer { fixture.close() }
            fixture.place(6)
            let cursor = try fixture.position(at: 6)
            let delegate = fixture.delegate
            let controller = fixture.controller

            let labels = CompletionLabelRecorder()
            let request = Task { @MainActor in
                let result = await delegate.completionSuggestionsRequested(textView: controller, cursorPosition: cursor)
                labels.labels = result?.items.map(\.label)
            }
            try await eventually { gate.waiterCount == 1 }
            fixture.textView.selectionManager.setSelectedRanges([])
            gate.open()
            await request.value

            #expect(labels.labels == ["foo"])
        }
    }

    @Test func aFailingResolveStillInsertsTheItem() async throws {
        try await withTempDir { directory in
            let caps = capabilities(resolve: true)
            let scripted = ScriptedServerConnection(capabilities: caps)
            let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.completionItemResolve])
            let server = try await SyncTestServer.makeServer(connection: failing, capabilities: caps)
            let harness = SyncTestServer(connection: scripted, server: server)
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = fo\n",
                completion: list([item("foo")]),
                harness: harness
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 10).first)
            fixture.apply(foo)
            try await eventually { fixture.text == "let x = foo\n" }
            #expect(foo.state.isResolved)
        }
    }

    @Test func serversWithoutResolveSupportNeverReceiveTheRequest() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = ",
                completion: list([item("foo")])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 4).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            #expect(foo.state.isResolved)
            #expect(fixture.connection.requestCount(.completionItemResolve) == 0)
        }
    }

    @Test func aFinishedResolutionRefreshesTheSuggestionPreview() async throws {
        @MainActor
        final class SelectionRecorder: NSObject, NSTableViewDataSource, NSTableViewDelegate {
            var selections = 0

            func numberOfRows(in tableView: NSTableView) -> Int {
                1
            }

            func tableViewSelectionDidChange(_ notification: Notification) {
                selections += 1
            }
        }
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = ",
                completion: list([item("foo")]),
                capabilities: capabilities(resolve: true)
            )
            defer { fixture.close() }
            let recorder = SelectionRecorder()
            let table = NSTableView()
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
            table.dataSource = recorder
            table.delegate = recorder
            table.reloadData()
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            let child = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            child.isReleasedWhenClosed = false
            child.contentView = table
            fixture.hosted.window.addChildWindow(child, ordered: .above)
            defer { fixture.hosted.window.removeChildWindow(child) }
            recorder.selections = 0

            try fixture.connection.script(.completionItemResolve, CompletionItem(label: "foo", detail: "d"))
            let foo = try #require(try await fixture.request(at: 4).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            try await eventually { recorder.selections == 1 }
        }
    }

    @Test func aResolutionOfAnItemThatIsNoLongerSelectedDoesNotRefresh() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = ",
                completion: list([item("foo"), item("bar")]),
                capabilities: capabilities(resolve: true)
            )
            defer { fixture.close() }
            let items = try await fixture.request(at: 4)
            let first = try #require(items.first { $0.label == "bar" })
            let second = try #require(items.first { $0.label == "foo" })
            fixture.delegate.completionWindowDidSelect(item: first)
            fixture.delegate.completionWindowDidSelect(item: second)
            try await eventually { first.state.isResolved && second.state.isResolved }
        }
    }

    @Test func incompleteListsAreRequestedAgainWhileTyping() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = f",
                completion: list(incomplete: true, [item("foo"), item("fob")])
            )
            defer { fixture.close() }
            #expect(try await fixture.request(at: 9).count == 2)
            try fixture.connection.script(
                .textDocumentCompletion,
                SyncTestServer.decode(CompletionList.self, list([item("foobar")]))
            )

            fixture.textView.replaceCharacters(in: NSRange(location: 9, length: 0), with: "o")
            let stale = try #require(try fixture.moved(to: 10))
            #expect(stale.map(\.label) == ["fob", "foo"])
            try await eventually { fixture.connection.requestCount(.textDocumentCompletion) == 2 }

            try await eventually {
                (try? fixture.moved(to: 10))?.map(\.label) == ["foobar"]
            }
            let params = fixture.connection.requests.compactMap { request -> CompletionParams? in
                if case let .completion(params, _) = request { return params }
                return nil
            }
            #expect(params.count == 2)
            #expect(params.last?.context?.triggerKind == .triggerForIncompleteCompletions)
            #expect(params.last?.context?.triggerCharacter == nil)
            #expect(params.last?.position == Position(line: 0, character: 10))

            fixture.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "o")
            _ = try fixture.moved(to: 11)
            for _ in 0..<10 { await Task.yield() }
            #expect(fixture.connection.requestCount(.textDocumentCompletion) == 2)
        }
    }

    @Test func aSecondRequestWhileTheFirstIsPendingSupersedesIt() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "let x = f",
                completion: list(incomplete: true, [item("foo")])
            )
            defer { fixture.close() }
            _ = try await fixture.request(at: 9)
            fixture.textView.replaceCharacters(in: NSRange(location: 9, length: 0), with: "o")
            _ = try fixture.moved(to: 10)
            fixture.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "o")
            _ = try fixture.moved(to: 11)
            try await eventually { fixture.connection.requestCount(.textDocumentCompletion) >= 2 }
        }
    }

    @Test func completionOnCursorMoveWithoutSuggestionsReturnsNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = ")
            defer { fixture.close() }
            #expect(try fixture.moved(to: 4) == nil)
        }
    }

    @Test func commitCharactersInsertTheSelectedItem() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: #","commitCharacters":["."]"#)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            fixture.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: ".")
            #expect(try fixture.moved(to: 7) == nil)
            try await eventually { fixture.text == "x = foo." }
            #expect(fixture.selection == NSRange(location: 8, length: 0))
        }
    }

    @Test func charactersThatDoNotCommitKeepTheListAndMovingTheCaretNeverCommits() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo.",
                completion: list([item("foo", extra: #","commitCharacters":["."]"#)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.delegate.completionWindowDidSelect(item: foo)

            #expect(try fixture.moved(to: 7) != nil)
            for _ in 0..<10 { await Task.yield() }
            #expect(fixture.text == "x = fo.")

            fixture.textView.replaceCharacters(in: NSRange(location: 7, length: 0), with: ",")
            #expect(try fixture.moved(to: 8) != nil)
            for _ in 0..<10 { await Task.yield() }
            #expect(fixture.text == "x = fo.,")
        }
    }

    @Test func nothingCommitsWithoutASelectedItem() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: #","commitCharacters":["."]"#)])
            )
            defer { fixture.close() }
            _ = try await fixture.request(at: 6)
            fixture.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: ".")
            #expect(try fixture.moved(to: 7) != nil)
        }
    }

    @Test func serverWideCommitCharactersApplyToItemsWithoutTheirOwn() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo"), item("fob", extra: #","commitCharacters":["!"]"#)]),
                capabilities: capabilities(commit: [";"])
            )
            defer { fixture.close() }
            let items = try await fixture.request(at: 6)
            #expect(items.first { $0.label == "foo" }?.commitCharacters == [";"])
            #expect(items.first { $0.label == "fob" }?.commitCharacters == ["!"])
        }
    }

    @Test func committingASnippetInsertsItsPlainText() async throws {
        try await withTempDir { directory in
            let extra = #","insertTextFormat":2,"insertText":"foo(${1:a})","commitCharacters":["."]"#
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.delegate.completionWindowDidSelect(item: foo)
            fixture.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: ".")
            _ = try fixture.moved(to: 7)
            try await eventually { fixture.text == "x = foo(a)." }
            #expect(fixture.delegate.snippetSession == nil)
        }
    }

    @Test func snippetItemsStartASessionThatTabsThroughItsStops() async throws {
        try await withTempDir { directory in
            let extra = #","insertTextFormat":2,"insertText":"foo(${1:a}, ${2:b})$0""#
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.apply(foo)
            #expect(fixture.text == "x = foo(a, b)")
            let session = try #require(fixture.delegate.snippetSession)
            #expect(session.isActive)
            #expect(fixture.selection == NSRange(location: 8, length: 1))

            _ = session.handle(try fixture.tab())
            #expect(fixture.selection == NSRange(location: 11, length: 1))
            fixture.textView.insertText("zz")
            #expect(fixture.text == "x = foo(a, zz)")
            _ = session.handle(try fixture.tab())
            #expect(!session.isActive)
            #expect(fixture.delegate.snippetSession == nil)
            #expect(fixture.selection == NSRange(location: 14, length: 0))
        }
    }

    @Test func aNewCompletionEndsThePreviousSnippetSession() async throws {
        try await withTempDir { directory in
            let extra = #","insertTextFormat":2,"insertText":"foo(${1:a})""#
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.apply(foo)
            let first = try #require(fixture.delegate.snippetSession)
            fixture.place(8)
            fixture.textView.replaceCharacters(in: NSRange(location: 8, length: 1), with: "b")
            fixture.place(9)
            fixture.apply(foo, cursorPosition: try fixture.position(at: 9))
            #expect(!first.isActive)
        }
    }

    @Test func snippetVariablesResolveAgainstTheDocument() async throws {
        try await withTempDir { directory in
            let extra = #","insertTextFormat":2,"insertText":"${TM_FILENAME}:${TM_LINE_NUMBER}:${TM_CURRENT_WORD}""#
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.apply(foo)
            #expect(fixture.text == "x = doc.swift:1:fo")
            #expect(fixture.delegate.snippetSession == nil)
            #expect(fixture.selection == NSRange(location: 18, length: 0))
        }
    }

    @Test func uneditableDocumentsAreLeftAlone() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo")])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.textView.isEditable = false
            fixture.apply(foo)
            #expect(fixture.text == "x = fo")
            #expect(fixture.delegate.snippetSession == nil)
        }
    }

    @Test func resettingTheDelegateEndsTheSession() async throws {
        try await withTempDir { directory in
            let extra = #","insertTextFormat":2,"insertText":"foo(${1:a})""#
            let fixture = try await makeFixture(
                in: directory,
                text: "x = fo",
                completion: list([item("foo", extra: extra)])
            )
            defer { fixture.close() }
            let foo = try #require(try await fixture.request(at: 6).first)
            fixture.apply(foo)
            let session = try #require(fixture.delegate.snippetSession)
            fixture.delegate.reset()
            #expect(!session.isActive)
            #expect(fixture.delegate.snippetSession == nil)
        }
    }

    @Test func requestsAtAnInvalidOffsetOfferNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = ", completion: list([item("foo")]))
            defer { fixture.close() }
            fixture.textView.selectionManager.setSelectedRanges([])
            let result = await fixture.delegate.completionSuggestionsRequested(
                textView: fixture.controller,
                cursorPosition: CursorPosition(range: NSRange(location: 999, length: 0))
            )
            #expect(result == nil)
            #expect(fixture.connection.requestCount(.textDocumentCompletion) == 0)
        }
    }

    @Test func applyingWithoutAnyCaretDoesNothing() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = fo")
            defer { fixture.close() }
            fixture.textView.selectionManager.setSelectedRanges([])
            fixture.apply(LSPCompletionSuggestion(item: CompletionItem(label: "foo")))
            #expect(fixture.text == "x = fo")
        }
    }

    @Test func applyingWithoutAPriorRequestUsesTheCaret() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = fo")
            defer { fixture.close() }
            fixture.place(6)
            fixture.apply(LSPCompletionSuggestion(item: CompletionItem(label: "foo")))
            #expect(fixture.text == "x = foo")
            #expect(fixture.selection == NSRange(location: 7, length: 0))
        }
    }

    @Test func plainArrayResponsesAreComplete() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(in: directory, text: "x = fo")
            defer { fixture.close() }
            try fixture.connection.script(.textDocumentCompletion, [CompletionItem(label: "foo")])
            let items = try await fixture.request(at: 6)
            #expect(items.map(\.label) == ["foo"])
            fixture.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: "o")
            #expect(try fixture.moved(to: 7)?.map(\.label) == ["foo"])
            for _ in 0..<10 { await Task.yield() }
            #expect(fixture.connection.requestCount(.textDocumentCompletion) == 1)
        }
    }

    @Test func movingBeyondTheDocumentNeverRequestsAgain() async throws {
        try await withTempDir { directory in
            let fixture = try await makeFixture(
                in: directory,
                text: "x = f",
                completion: list(incomplete: true, [item("foo")])
            )
            defer { fixture.close() }
            _ = try await fixture.request(at: 5)
            let result = fixture.delegate.completionOnCursorMove(
                textView: fixture.controller,
                cursorPosition: CursorPosition(range: NSRange(location: 999, length: 0))
            )
            #expect(result?.count == 1)
            for _ in 0..<10 { await Task.yield() }
            #expect(fixture.connection.requestCount(.textDocumentCompletion) == 1)
        }
    }

    @Test func previewRefreshIgnoresMissingWindowsAndUnselectedTables() {
        LSPCompletionPreviewRefresher.refresh(parent: nil)
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        let empty = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        empty.isReleasedWhenClosed = false
        let container = NSView()
        container.addSubview(NSView())
        container.addSubview(NSTableView())
        empty.contentView = container
        let bare = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        bare.isReleasedWhenClosed = false
        bare.contentView = nil
        parent.addChildWindow(empty, ordered: .above)
        parent.addChildWindow(bare, ordered: .above)
        LSPCompletionPreviewRefresher.refresh(parent: parent)
        parent.removeChildWindow(empty)
        parent.removeChildWindow(bare)
    }
}

@MainActor
private final class CompletionLabelRecorder {
    var labels: [String]?
}
