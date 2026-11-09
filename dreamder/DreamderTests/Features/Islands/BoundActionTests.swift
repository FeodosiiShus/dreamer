import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BoundActionTests {
    @MainActor
    private final class Recorder {
        var received: [Int] = []
        var calls = 0

        func record(_ value: Int) {
            received.append(value)
        }

        func call() {
            calls += 1
        }
    }

    private struct Sample {
        let first: Int
        let second: String
    }

    @Test
    func boundActionDeliversItsValueEachTimeItRuns() {
        let recorder = Recorder()
        let action = bound(recorder.record, 7)

        #expect(recorder.received.isEmpty)
        action()
        action()

        #expect(recorder.received == [7, 7])
    }

    @Test
    func discardingActionIgnoresTheValueItIsGiven() {
        let recorder = Recorder()
        let action: (String) -> Void = discarding(recorder.call)

        action("ignored")
        action("also ignored")

        #expect(recorder.calls == 2)
    }

    @Test
    func readingActionPassesTheKeyPathValue() {
        let recorder = Recorder()
        let action: (Sample) -> Void = reading(\.first, into: recorder.record)

        action(Sample(first: 3, second: "a"))

        #expect(recorder.received == [3])
    }

    @Test
    func readingActionPassesTwoKeyPathValuesAndReturnsTheResult() {
        let action: (Sample) -> String = reading(\.first, \.second, into: { "\($1)\($0)" })

        #expect(action(Sample(first: 4, second: "x")) == "x4")
    }
}
