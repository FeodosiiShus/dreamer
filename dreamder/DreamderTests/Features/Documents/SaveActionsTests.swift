import Foundation
import Testing
@testable import Dreamder

@Suite
struct SaveActionsTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let trim: Bool
        let finalNewline: Bool
        let input: String
        let expected: String
        var fallback = "\n"

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "nothing enabled", trim: false, finalNewline: false, input: "a  \nb", expected: "a  \nb"),
        Case(name: "trim spaces", trim: true, finalNewline: false, input: "a  \nb\t\n", expected: "a\nb\n"),
        Case(name: "trim tab and space mix", trim: true, finalNewline: false, input: "a \t \nb", expected: "a\nb"),
        Case(name: "trim keeps leading indentation", trim: true, finalNewline: false, input: "  a  \n", expected: "  a\n"),
        Case(name: "trim whitespace only lines", trim: true, finalNewline: false, input: "a\n   \nb\n", expected: "a\n\nb\n"),
        Case(name: "trim crlf", trim: true, finalNewline: false, input: "a  \r\nb \r\n", expected: "a\r\nb\r\n"),
        Case(name: "trim cr", trim: true, finalNewline: false, input: "a  \rb \r", expected: "a\rb\r"),
        Case(name: "trim last line without newline", trim: true, finalNewline: false, input: "a\nb  ", expected: "a\nb"),
        Case(name: "trim leaves inner spaces", trim: true, finalNewline: false, input: "a b  c  \n", expected: "a b  c\n"),
        Case(name: "trim only whitespace file", trim: true, finalNewline: false, input: "   ", expected: ""),
        Case(name: "final newline added", trim: false, finalNewline: true, input: "a\nb", expected: "a\nb\n"),
        Case(name: "final newline already there", trim: false, finalNewline: true, input: "a\nb\n", expected: "a\nb\n"),
        Case(name: "final newline after cr", trim: false, finalNewline: true, input: "a\r", expected: "a\r"),
        Case(name: "final newline follows crlf", trim: false, finalNewline: true, input: "a\r\nb", expected: "a\r\nb\r\n"),
        Case(name: "final newline follows cr", trim: false, finalNewline: true, input: "a\rb", expected: "a\rb\r"),
        Case(name: "final newline follows lf", trim: false, finalNewline: true, input: "a\nb\r\nc", expected: "a\nb\r\nc\n"),
        Case(name: "final newline of a cr cr lf file is a lone cr", trim: false, finalNewline: true, input: "a\r\r\nb", expected: "a\r\r\nb\r"),
        Case(name: "final newline falls back to the configured ending", trim: false, finalNewline: true, input: "abc", expected: "abc\r\n", fallback: "\r\n"),
        Case(name: "final newline keeps empty files empty", trim: false, finalNewline: true, input: "", expected: ""),
        Case(name: "both on a trailing whitespace line", trim: true, finalNewline: true, input: "a  ", expected: "a\n"),
        Case(name: "both on a trailing whitespace only line", trim: true, finalNewline: true, input: "a\n  ", expected: "a\n"),
        Case(name: "both on a whitespace only file", trim: true, finalNewline: true, input: "  ", expected: ""),
        Case(name: "trailing whitespace stays when trim is off", trim: false, finalNewline: true, input: "a  ", expected: "a  \n"),
        Case(name: "unicode content", trim: true, finalNewline: true, input: "h\u{00E9}llo \u{1F600}  \nz", expected: "h\u{00E9}llo \u{1F600}\nz\n")
    ]

    @Test(arguments: cases)
    func appliesEdits(_ testCase: Case) {
        let actions = SaveActions(
            trimTrailingWhitespace: testCase.trim,
            insertFinalNewline: testCase.finalNewline,
            fallbackLineEnding: testCase.fallback
        )
        let edits = actions.edits(for: testCase.input)

        #expect(SaveActions.apply(edits, to: testCase.input) == testCase.expected)
    }

    @Test
    func editsAreOrderedForApplicationFromTheEnd() {
        let actions = SaveActions(trimTrailingWhitespace: true, insertFinalNewline: true)
        let edits = actions.edits(for: "a \nb \nc ")

        #expect(edits.map(\.range.location) == [8, 7, 4, 1])
        #expect(edits.map(\.replacement) == ["\n", "", "", ""])
    }

    @Test
    func emptyConfigurationProducesNoEdits() {
        #expect(SaveActions(trimTrailingWhitespace: false, insertFinalNewline: false).edits(for: "a  ").isEmpty)
        #expect(SaveActions(trimTrailingWhitespace: false, insertFinalNewline: false).isEmpty)
        #expect(!SaveActions(trimTrailingWhitespace: true, insertFinalNewline: false).isEmpty)
        #expect(!SaveActions(trimTrailingWhitespace: false, insertFinalNewline: true).isEmpty)
    }

    struct ConfigCase: Sendable, CustomTestStringConvertible {
        let name: String
        let properties: EditorConfigProperties
        var settings = SaveActionSettings(
            trailingSpaces: .none,
            keepTrailingSpacesOnCaretLine: false,
            ensureFinalNewline: false
        )
        let expected: SaveActions

        var testDescription: String { name }
    }

    static let configCases: [ConfigCase] = [
        ConfigCase(
            name: "empty",
            properties: .empty,
            expected: SaveActions(trimTrailingWhitespace: false, insertFinalNewline: false)
        ),
        ConfigCase(
            name: "explicitly false",
            properties: EditorConfigProperties(insertFinalNewline: false, trimTrailingWhitespace: false),
            expected: SaveActions(trimTrailingWhitespace: false, insertFinalNewline: false)
        ),
        ConfigCase(
            name: "both enabled with lf",
            properties: EditorConfigProperties(endOfLine: .lf, insertFinalNewline: true, trimTrailingWhitespace: true),
            expected: SaveActions(trimTrailingWhitespace: true, insertFinalNewline: true, fallbackLineEnding: "\n")
        ),
        ConfigCase(
            name: "crlf",
            properties: EditorConfigProperties(endOfLine: .crlf, insertFinalNewline: true),
            expected: SaveActions(trimTrailingWhitespace: false, insertFinalNewline: true, fallbackLineEnding: "\r\n")
        ),
        ConfigCase(
            name: "cr",
            properties: EditorConfigProperties(endOfLine: .cr, trimTrailingWhitespace: true),
            expected: SaveActions(trimTrailingWhitespace: true, insertFinalNewline: false, fallbackLineEnding: "\r")
        ),
        ConfigCase(
            name: "settings apply when editorconfig is silent",
            properties: .empty,
            settings: SaveActionSettings(
                trailingSpaces: .modifiedLines,
                keepTrailingSpacesOnCaretLine: true,
                ensureFinalNewline: true
            ),
            expected: SaveActions(
                trimMode: .modifiedLines,
                keepTrailingSpacesOnCaretLine: true,
                insertFinalNewline: true
            )
        ),
        ConfigCase(
            name: "editorconfig true wins over the none setting",
            properties: EditorConfigProperties(insertFinalNewline: true, trimTrailingWhitespace: true),
            expected: SaveActions(trimMode: .allLines, keepTrailingSpacesOnCaretLine: false, insertFinalNewline: true)
        ),
        ConfigCase(
            name: "editorconfig false wins over enabled settings",
            properties: EditorConfigProperties(insertFinalNewline: false, trimTrailingWhitespace: false),
            settings: SaveActionSettings(
                trailingSpaces: .allLines,
                keepTrailingSpacesOnCaretLine: true,
                ensureFinalNewline: true
            ),
            expected: SaveActions(trimMode: .none, keepTrailingSpacesOnCaretLine: true, insertFinalNewline: false)
        ),
        ConfigCase(
            name: "editorconfig true turns modified lines into all lines",
            properties: EditorConfigProperties(trimTrailingWhitespace: true),
            settings: SaveActionSettings(
                trailingSpaces: .modifiedLines,
                keepTrailingSpacesOnCaretLine: true,
                ensureFinalNewline: false
            ),
            expected: SaveActions(trimMode: .allLines, keepTrailingSpacesOnCaretLine: true, insertFinalNewline: false)
        )
    ]

    @Test(arguments: configCases)
    func readsTheEditorConfigPropertiesAndSettings(_ testCase: ConfigCase) {
        #expect(SaveActions(editorConfig: testCase.properties, settings: testCase.settings) == testCase.expected)
    }

    @Test
    func defaultSettingsMatchIntelliJ() {
        let settings = SaveActionSettings()

        #expect(settings.trailingSpaces == .modifiedLines)
        #expect(settings.keepTrailingSpacesOnCaretLine)
        #expect(!settings.ensureFinalNewline)
    }

    struct ModeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let mode: TrailingSpacesMode
        let keepCaret: Bool
        let finalNewline: Bool
        let input: String
        let modified: [Int]
        let carets: [Int]
        let expected: String
        let deferred: [Int]

        var testDescription: String { name }
    }

    static let modeCases: [ModeCase] = [
        ModeCase(
            name: "modified lines keep untouched trailing spaces",
            mode: .modifiedLines, keepCaret: false, finalNewline: false,
            input: "a  \nb  \nc  \n", modified: [1], carets: [],
            expected: "a  \nb\nc  \n", deferred: []
        ),
        ModeCase(
            name: "all lines strip every line",
            mode: .allLines, keepCaret: false, finalNewline: false,
            input: "a  \nb  \nc  \n", modified: [1], carets: [],
            expected: "a\nb\nc\n", deferred: []
        ),
        ModeCase(
            name: "none strips nothing",
            mode: .none, keepCaret: false, finalNewline: false,
            input: "a  \nb  \n", modified: [0, 1], carets: [],
            expected: "a  \nb  \n", deferred: []
        ),
        ModeCase(
            name: "modified lines without modifications change nothing",
            mode: .modifiedLines, keepCaret: false, finalNewline: false,
            input: "a  \nb  \n", modified: [], carets: [],
            expected: "a  \nb  \n", deferred: []
        ),
        ModeCase(
            name: "caret inside trailing spaces keeps the line",
            mode: .allLines, keepCaret: true, finalNewline: false,
            input: "a  \nb  \nc  \n", modified: [], carets: [6],
            expected: "a\nb  \nc\n", deferred: []
        ),
        ModeCase(
            name: "caret at the end of trailing spaces keeps the line",
            mode: .allLines, keepCaret: true, finalNewline: false,
            input: "a  \nb  \n", modified: [], carets: [7],
            expected: "a\nb  \n", deferred: []
        ),
        ModeCase(
            name: "caret before the trailing spaces still strips",
            mode: .allLines, keepCaret: true, finalNewline: false,
            input: "a  \nb  \n", modified: [], carets: [4],
            expected: "a\nb\n", deferred: []
        ),
        ModeCase(
            name: "caret line is stripped when the option is off",
            mode: .allLines, keepCaret: false, finalNewline: false,
            input: "a  \nb  \n", modified: [], carets: [6],
            expected: "a\nb\n", deferred: []
        ),
        ModeCase(
            name: "modified caret line is deferred in modified mode",
            mode: .modifiedLines, keepCaret: true, finalNewline: false,
            input: "a  \nb  \nc  \n", modified: [1, 2], carets: [6],
            expected: "a  \nb  \nc\n", deferred: [1]
        ),
        ModeCase(
            name: "caret in a crlf file",
            mode: .allLines, keepCaret: true, finalNewline: false,
            input: "a  \r\nb  \r\nc  ", modified: [], carets: [8],
            expected: "a\r\nb  \r\nc", deferred: []
        ),
        ModeCase(
            name: "untouched whitespace only last line is removed for the final newline",
            mode: .modifiedLines, keepCaret: true, finalNewline: true,
            input: "a\n   ", modified: [], carets: [],
            expected: "a\n", deferred: []
        ),
        ModeCase(
            name: "caret on a whitespace only last line gets a newline instead",
            mode: .modifiedLines, keepCaret: true, finalNewline: true,
            input: "a\n   ", modified: [], carets: [5],
            expected: "a\n   \n", deferred: []
        ),
        ModeCase(
            name: "whitespace only last line without trimming gets a newline",
            mode: .none, keepCaret: true, finalNewline: true,
            input: "a\n   ", modified: [], carets: [],
            expected: "a\n   \n", deferred: []
        ),
        ModeCase(
            name: "single whitespace only line is emptied in modified mode",
            mode: .modifiedLines, keepCaret: false, finalNewline: true,
            input: "  ", modified: [], carets: [],
            expected: "", deferred: []
        )
    ]

    @Test(arguments: modeCases)
    func appliesModesWithModifiedLinesAndCarets(_ testCase: ModeCase) {
        let actions = SaveActions(
            trimMode: testCase.mode,
            keepTrailingSpacesOnCaretLine: testCase.keepCaret,
            insertFinalNewline: testCase.finalNewline
        )
        let plan = actions.plan(
            for: testCase.input,
            modifiedLines: IndexSet(testCase.modified),
            caretOffsets: testCase.carets
        )

        #expect(SaveActions.apply(plan.edits, to: testCase.input) == testCase.expected)
        #expect(plan.deferredLines == IndexSet(testCase.deferred))
    }

    @Test
    func trackerMarksTheEditedLine() {
        var tracker = ModifiedLineTracker()
        tracker.replace(startLine: 3, removedLineBreaks: 0, addedLineBreaks: 0)

        #expect(tracker.lines == IndexSet([3]))
    }

    @Test
    func trackerShiftsLaterLinesWhenLinesAreInserted() {
        var tracker = ModifiedLineTracker()
        tracker.replace(startLine: 1, removedLineBreaks: 0, addedLineBreaks: 0)
        tracker.replace(startLine: 5, removedLineBreaks: 0, addedLineBreaks: 0)
        tracker.replace(startLine: 2, removedLineBreaks: 0, addedLineBreaks: 2)

        #expect(tracker.lines == IndexSet([1, 2, 3, 4, 7]))
    }

    @Test
    func trackerCollapsesRemovedLinesAndShiftsTheRest() {
        var tracker = ModifiedLineTracker()
        for line in [1, 2, 3, 6] {
            tracker.replace(startLine: line, removedLineBreaks: 0, addedLineBreaks: 0)
        }
        tracker.replace(startLine: 1, removedLineBreaks: 2, addedLineBreaks: 0)

        #expect(tracker.lines == IndexSet([1, 4]))
    }

    @Test
    func trackerHandlesReplacementsThatChangeTheLineCount() {
        var tracker = ModifiedLineTracker()
        tracker.replace(startLine: 0, removedLineBreaks: 0, addedLineBreaks: 0)
        tracker.replace(startLine: 4, removedLineBreaks: 0, addedLineBreaks: 0)
        tracker.replace(startLine: 1, removedLineBreaks: 1, addedLineBreaks: 3)

        #expect(tracker.lines == IndexSet([0, 1, 2, 3, 4, 6]))
    }

    @Test
    func trackerResetKeepsRetainedLines() {
        var tracker = ModifiedLineTracker()
        tracker.replace(startLine: 1, removedLineBreaks: 0, addedLineBreaks: 0)
        tracker.reset(keeping: IndexSet([4]))
        #expect(tracker.lines == IndexSet([4]))
        tracker.reset()
        #expect(tracker.lines.isEmpty)
    }

    @Test
    func lineBreakCountTreatsCrLfAsOne() {
        #expect(ModifiedLineTracker.lineBreakCount(in: "") == 0)
        #expect(ModifiedLineTracker.lineBreakCount(in: "abc") == 0)
        #expect(ModifiedLineTracker.lineBreakCount(in: "a\nb\n") == 2)
        #expect(ModifiedLineTracker.lineBreakCount(in: "a\r\nb\r\n") == 2)
        #expect(ModifiedLineTracker.lineBreakCount(in: "a\rb\r") == 2)
        #expect(ModifiedLineTracker.lineBreakCount(in: "a\r\rb") == 2)
        #expect(ModifiedLineTracker.lineBreakCount(in: "\n\r\n\r") == 3)
    }

    @Test
    func mapKeepsOffsetsBeforeEditsAndShiftsOffsetsAfterThem() {
        let edits = [
            SaveTextEdit(range: NSRange(location: 10, length: 3), replacement: ""),
            SaveTextEdit(range: NSRange(location: 4, length: 2), replacement: "")
        ]

        #expect(SaveActions.map(0, through: edits) == 0)
        #expect(SaveActions.map(4, through: edits) == 4)
        #expect(SaveActions.map(5, through: edits) == 4)
        #expect(SaveActions.map(6, through: edits) == 4)
        #expect(SaveActions.map(8, through: edits) == 6)
        #expect(SaveActions.map(11, through: edits) == 8)
        #expect(SaveActions.map(13, through: edits) == 8)
        #expect(SaveActions.map(20, through: edits) == 15)
    }

    @Test
    func mapKeepsACaretAtTheEndInPlaceWhenANewlineIsAppended() {
        let edits = [SaveTextEdit(range: NSRange(location: 5, length: 0), replacement: "\r\n")]

        #expect(SaveActions.map(5, through: edits) == 5)
        #expect(SaveActions.map(3, through: edits) == 3)
        #expect(SaveActions.map(7, through: edits) == 9)
    }

    @Test
    func mapRemapsRanges() {
        let edits = [SaveTextEdit(range: NSRange(location: 2, length: 2), replacement: "")]

        #expect(SaveActions.map(NSRange(location: 0, length: 1), through: edits) == NSRange(location: 0, length: 1))
        #expect(SaveActions.map(NSRange(location: 1, length: 5), through: edits) == NSRange(location: 1, length: 3))
        #expect(SaveActions.map(NSRange(location: 3, length: 0), through: edits) == NSRange(location: 2, length: 0))
        #expect(SaveActions.map(NSRange(location: 6, length: 2), through: edits) == NSRange(location: 4, length: 2))
    }

    @Test
    func lengthDeltaCountsUtf16Units() {
        #expect(SaveTextEdit(range: NSRange(location: 0, length: 3), replacement: "").lengthDelta == -3)
        #expect(SaveTextEdit(range: NSRange(location: 0, length: 0), replacement: "\r\n").lengthDelta == 2)
        #expect(SaveTextEdit(range: NSRange(location: 0, length: 1), replacement: "\u{1F600}").lengthDelta == 1)
    }
}
