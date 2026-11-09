import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GoToLinePopupModelTests {
    private final class Recorder {
        var submitted: [GoToLineTarget] = []
        var dismissals = 0
    }

    private func makeModel(_ recorder: Recorder) -> GoToLinePopupModel {
        GoToLinePopupModel(
            lineCount: 40,
            currentLine: 12,
            currentColumn: 5,
            onSubmit: { recorder.submitted.append($0) },
            onDismiss: { recorder.dismissals += 1 }
        )
    }

    @Test func startsWithTheCaretPositionAndTexts() {
        let model = makeModel(Recorder())
        #expect(model.input == "12:5")
        #expect(model.title == "Go to Line/Column")
        #expect(model.placeholder == "Line:column (1–40)")
        #expect(model.target == GoToLineTarget(line: 12, column: 5))
        #expect(model.isValid)
    }

    @Test func submitsAValidTargetAndDismisses() {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.input = "7:2"
        model.submit()
        #expect(recorder.submitted == [GoToLineTarget(line: 7, column: 2)])
        #expect(recorder.dismissals == 1)
    }

    @Test func clampsTheLineOnSubmit() {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.input = "500"
        model.submit()
        #expect(recorder.submitted == [GoToLineTarget(line: 40, column: 1)])
    }

    @Test func invalidInputDoesNothing() {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.input = "abc"
        #expect(!model.isValid)
        #expect(model.target == nil)
        model.submit()
        #expect(recorder.submitted.isEmpty)
        #expect(recorder.dismissals == 0)
    }

    @Test func cancelOnlyDismisses() {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.cancel()
        #expect(recorder.submitted.isEmpty)
        #expect(recorder.dismissals == 1)
    }

    @Test func defaultDismissHandlerIsANoOp() {
        let recorder = Recorder()
        let model = GoToLinePopupModel(
            lineCount: 3,
            currentLine: 1,
            currentColumn: 1,
            onSubmit: { recorder.submitted.append($0) }
        )
        model.submit()
        model.cancel()
        #expect(recorder.submitted == [GoToLineTarget(line: 1, column: 1)])
    }
}
