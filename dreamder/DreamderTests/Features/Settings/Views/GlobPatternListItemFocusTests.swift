import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class GlobPatternFocusSink {
    var item: GlobPatternListItem?
    var selection: Set<UUID> = []
}

private struct GlobPatternFocusProbe: View {
    @FocusState private var focus: String?
    @State var pattern: GlobPattern
    let sink: GlobPatternFocusSink

    var body: some View {
        let item = GlobPatternListItem(
            pattern: $pattern,
            selection: Binding(get: { sink.selection }, set: { sink.selection = $0 }),
            addPattern: {},
            removePatterns: { _ in },
            focusedField: $focus,
            isLast: true
        )
        sink.item = item
        return item
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct GlobPatternListItemFocusTests {
    @Test
    func gainingFocusSelectsThePattern() async throws {
        let pattern = GlobPattern(value: "*.log")
        let sink = GlobPatternFocusSink()
        let host = HostedViewFixture.host(size: NSSize(width: 240, height: 60)) {
            GlobPatternFocusProbe(pattern: pattern, sink: sink)
        }
        defer { host.close() }
        try await host.settle(.milliseconds(150))
        let item = try #require(sink.item)

        item.focusDidChange(from: false, to: true)

        #expect(sink.selection == [pattern.id])
    }
}
