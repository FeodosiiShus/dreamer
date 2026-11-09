import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("CodeActionsMapping")
struct CodeActionsMappingTests {
    private func diagnostic(_ message: String, line: Int = 0, from: Int = 0, to: Int = 3) -> Diagnostic {
        Diagnostic(
            range: LSPRange(startPair: (line, from), endPair: (line, to)),
            severity: .error,
            source: "swift",
            message: message
        )
    }

    private func edit() -> WorkspaceEdit {
        WorkspaceEdit(changes: ["file:///a.swift": []], documentChanges: nil)
    }

    private static let disabledMarker: CodeAction.Disabled? = try? JSONDecoder().decode(
        CodeAction.Disabled.self,
        from: Data(#"{"disabled":true}"#.utf8)
    )

    private func action(
        _ title: String,
        kind: CodeActionKind? = nil,
        diagnostics: [Diagnostic]? = nil,
        preferred: Bool? = nil,
        disabled: Bool = false
    ) -> TwoTypeOption<LSPCommand, CodeAction> {
        .optionB(CodeAction(
            title: title,
            kind: kind,
            diagnostics: diagnostics,
            isPreferred: preferred,
            disabled: disabled ? Self.disabledMarker : nil,
            edit: edit()
        ))
    }

    private func command(_ title: String) -> TwoTypeOption<LSPCommand, CodeAction> {
        .optionA(LSPCommand(title: title, command: "do.\(title)", arguments: nil))
    }

    @Test
    func nilResponseYieldsNoGroups() {
        #expect(LSPCodeActionMapping.groups(from: nil, diagnostics: []).isEmpty)
        #expect(LSPCodeActionMapping.groups(from: [], diagnostics: []).isEmpty)
    }

    struct CategoryCase: Sendable, CustomTestStringConvertible {
        let kind: CodeActionKind?
        let hasDiagnostics: Bool
        let expected: IntentionCategory

        var testDescription: String { "\(kind ?? "nil")/\(hasDiagnostics) -> \(expected)" }
    }

    @Test(arguments: [
        CategoryCase(kind: "quickfix", hasDiagnostics: false, expected: .quickFix),
        CategoryCase(kind: "quickfix.import", hasDiagnostics: false, expected: .quickFix),
        CategoryCase(kind: "refactor", hasDiagnostics: true, expected: .refactoring),
        CategoryCase(kind: "refactor.extract", hasDiagnostics: false, expected: .refactoring),
        CategoryCase(kind: "refactor.inline", hasDiagnostics: false, expected: .refactoring),
        CategoryCase(kind: "refactor.rewrite", hasDiagnostics: false, expected: .refactoring),
        CategoryCase(kind: "source", hasDiagnostics: true, expected: .source),
        CategoryCase(kind: "source.organizeImports", hasDiagnostics: false, expected: .source),
        CategoryCase(kind: "source.fixAll", hasDiagnostics: false, expected: .source),
        CategoryCase(kind: nil, hasDiagnostics: true, expected: .quickFix),
        CategoryCase(kind: nil, hasDiagnostics: false, expected: .refactoring),
        CategoryCase(kind: "", hasDiagnostics: true, expected: .quickFix),
        CategoryCase(kind: "notebook", hasDiagnostics: false, expected: .refactoring),
        CategoryCase(kind: "notebook", hasDiagnostics: true, expected: .quickFix),
        CategoryCase(kind: "quickfixes", hasDiagnostics: false, expected: .refactoring)
    ])
    func kindsMapToCategories(_ item: CategoryCase) {
        #expect(LSPCodeActionMapping.category(forKind: item.kind, hasDiagnostics: item.hasDiagnostics) == item.expected)
    }

    @Test
    func groupsAreSortedQuickFixThenRefactoringThenSourceKeepingServerOrder() {
        let error = diagnostic("cannot find x")
        let response = [
            action("Organize", kind: "source.organizeImports"),
            action("Extract", kind: "refactor.extract"),
            action("Add import", kind: "quickfix", diagnostics: [error]),
            action("Fix all", kind: "source.fixAll"),
            action("Inline", kind: "refactor.inline")
        ]

        let groups = LSPCodeActionMapping.groups(from: response, diagnostics: [error])

        #expect(groups.map(\.category) == [.quickFix, .refactoring, .source])
        #expect(groups.map(\.title) == ["cannot find x", "Refactorings", "Source Actions"])
        #expect(groups[1].actions.map(\.title) == ["Extract", "Inline"])
        #expect(groups[2].actions.map(\.title) == ["Organize", "Fix all"])
        #expect(groups.hasQuickFixes)
        #expect(groups.allActions.count == 5)
    }

    @Test
    func quickFixesAreGroupedByTheirDiagnosticMessage() {
        let first = diagnostic("first problem")
        let second = diagnostic("second problem", from: 5, to: 8)
        let response = [
            action("Fix B", kind: "quickfix", diagnostics: [second]),
            action("Fix A1", kind: "quickfix", diagnostics: [first]),
            action("Fix A2", kind: "quickfix", diagnostics: [first])
        ]

        let groups = LSPCodeActionMapping.groups(from: response, diagnostics: [first, second])

        #expect(groups.map(\.title) == ["second problem", "first problem"])
        #expect(groups[1].actions.map(\.title) == ["Fix A1", "Fix A2"])
    }

    @Test
    func quickFixWithoutActionDiagnosticsUsesTheOnlyContextDiagnosticOrTheCategoryTitle() {
        let only = diagnostic("lonely")
        let single = LSPCodeActionMapping.groups(from: [action("Fix", kind: "quickfix")], diagnostics: [only])
        let several = LSPCodeActionMapping.groups(
            from: [action("Fix", kind: "quickfix")],
            diagnostics: [only, diagnostic("other")]
        )
        let none = LSPCodeActionMapping.groups(from: [action("Fix", kind: "quickfix")], diagnostics: [])

        #expect(single.map(\.title) == ["lonely"])
        #expect(several.map(\.title) == ["Quick Fixes"])
        #expect(none.map(\.title) == ["Quick Fixes"])
    }

    @Test
    func preferredActionsComeFirstAndDisabledActionsAreDropped() {
        let response = [
            action("Plain", kind: "refactor"),
            action("Hidden", kind: "refactor", disabled: true),
            action("Best", kind: "refactor", preferred: true)
        ]

        let groups = LSPCodeActionMapping.groups(from: response, diagnostics: [])

        #expect(groups.count == 1)
        #expect(groups[0].actions.map(\.title) == ["Best", "Plain"])
        #expect(groups[0].actions.map(\.isPreferred) == [true, false])
    }

    @Test
    func bareCommandsBecomeQuickFixesOnlyWhenDiagnosticsExist() {
        let withDiagnostics = LSPCodeActionMapping.groups(from: [command("Legacy")], diagnostics: [diagnostic("bad")])
        let without = LSPCodeActionMapping.groups(from: [command("Legacy")], diagnostics: [])

        #expect(withDiagnostics.map(\.category) == [.quickFix])
        #expect(without.map(\.category) == [.refactoring])
        #expect(
            without.first?.actions.first?.payload
                == .command(LSPCommand(title: "Legacy", command: "do.Legacy", arguments: nil))
        )
    }

    @Test
    func intentionIdentifiersAreUnique() {
        let groups = LSPCodeActionMapping.groups(
            from: [action("Same", kind: "refactor"), action("Same", kind: "refactor")],
            diagnostics: []
        )

        let ids = groups.allActions.map(\.id)
        #expect(Set(ids).count == 2)
        #expect(!groups.hasQuickFixes)
    }

    @Test
    func categoriesAreOrderedAndTitled() {
        #expect(IntentionCategory.quickFix < .refactoring)
        #expect(IntentionCategory.refactoring < .source)
        #expect(IntentionCategory.allCases.map(\.title) == ["Quick Fixes", "Refactorings", "Source Actions"])
    }
}

@Suite("CodeActionsDiagnostics")
struct CodeActionsDiagnosticsTests {
    private let file = URL(fileURLWithPath: "/tmp/a.swift")

    private func workspaceDiagnostic(
        line: Int,
        from: Int,
        to: Int,
        endLine: Int? = nil,
        severity: WorkspaceDiagnostic.Severity = .error,
        source: String? = "swift",
        code: String? = nil
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: file,
            startLine: line,
            startColumn: from,
            endLine: endLine ?? line,
            endColumn: to,
            severity: severity,
            message: "m\(line):\(from)",
            source: source,
            code: code
        )
    }

    @Test
    func diagnosticsTouchingTheRangeAreSelectedAndConverted() {
        let inside = workspaceDiagnostic(line: 1, from: 2, to: 6, code: "42")
        let named = workspaceDiagnostic(line: 1, from: 8, to: 9, severity: .warning, code: "E0308")
        let elsewhere = workspaceDiagnostic(line: 3, from: 0, to: 4)
        let range = LSPRange(startPair: (1, 4), endPair: (1, 8))

        let result = LSPCodeActionDiagnostics.diagnostics(in: [inside, named, elsewhere], intersecting: range)

        #expect(result.count == 2)
        #expect(result[0].range == LSPRange(startPair: (1, 2), endPair: (1, 6)))
        #expect(result[0].severity == .error)
        #expect(result[0].code == .optionA(42))
        #expect(result[0].source == "swift")
        #expect(result[0].message == "m1:2")
        #expect(result[1].severity == .warning)
        #expect(result[1].code == .optionB("E0308"))
    }

    @Test
    func caretRangesTouchDiagnosticsAtTheirBoundaries() {
        let diagnostic = workspaceDiagnostic(line: 0, from: 4, to: 7, code: nil)

        let atStart = LSPCodeActionDiagnostics.diagnostics(
            in: [diagnostic],
            intersecting: LSPRange(startPair: (0, 4), endPair: (0, 4))
        )
        let atEnd = LSPCodeActionDiagnostics.diagnostics(
            in: [diagnostic],
            intersecting: LSPRange(startPair: (0, 7), endPair: (0, 7))
        )
        let before = LSPCodeActionDiagnostics.diagnostics(
            in: [diagnostic],
            intersecting: LSPRange(startPair: (0, 3), endPair: (0, 3))
        )

        #expect(atStart.count == 1)
        #expect(atEnd.count == 1)
        #expect(before.isEmpty)
        #expect(atStart[0].code == nil)
    }

    @Test
    func lineSelectionIncludesMultiLineDiagnostics() {
        let spanning = workspaceDiagnostic(line: 2, from: 1, to: 3, endLine: 5)
        let single = workspaceDiagnostic(line: 4, from: 0, to: 2)
        let other = workspaceDiagnostic(line: 8, from: 0, to: 2)

        let result = LSPCodeActionDiagnostics.diagnostics(in: [spanning, single, other], onLine: 4)

        #expect(result.map(\.message) == ["m2:1", "m4:0"])
    }

    @Test
    func coveringRangeSpansAllDiagnostics() {
        let first = LSPCodeActionDiagnostics.lspDiagnostic(from: workspaceDiagnostic(line: 1, from: 6, to: 9))
        let second = LSPCodeActionDiagnostics.lspDiagnostic(from: workspaceDiagnostic(line: 1, from: 2, to: 4))
        let third = LSPCodeActionDiagnostics.lspDiagnostic(from: workspaceDiagnostic(line: 2, from: 0, to: 1))

        #expect(LSPCodeActionDiagnostics.range(covering: []) == nil)
        #expect(LSPCodeActionDiagnostics.range(covering: [first]) == first.range)
        #expect(
            LSPCodeActionDiagnostics.range(covering: [first, second, third])
                == LSPRange(startPair: (1, 2), endPair: (2, 1))
        )
    }
}
