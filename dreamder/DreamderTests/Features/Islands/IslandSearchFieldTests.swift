import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Observable
private final class IslandSearchFieldTextModel {
    var text: String

    init(text: String) {
        self.text = text
    }
}

@MainActor
private final class IslandSearchFieldCallbacks {
    var clears = 0
    var submits = 0
}

@MainActor
private final class IslandSearchFieldProbe {
    var field: IslandSearchField?

    func capture(_ field: IslandSearchField) -> IslandSearchField {
        self.field = field
        return field
    }
}

private struct IslandSearchFieldInternalFocusHarness: View {
    let model: IslandSearchFieldTextModel
    let probe: IslandSearchFieldProbe

    var body: some View {
        probe.capture(IslandSearchField("Find", text: Bindable(model).text))
            .frame(width: 240, height: 40)
            .background(Color.black)
    }
}

private struct IslandSearchFieldExternalFocusHarness: View {
    let model: IslandSearchFieldTextModel
    let probe: IslandSearchFieldProbe
    @FocusState private var focused: Bool

    var body: some View {
        probe.capture(IslandSearchField("Find", text: Bindable(model).text, focus: $focused))
            .frame(width: 240, height: 40)
            .background(Color.black)
    }
}

@MainActor
@Suite(.uiGate)
struct IslandSearchFieldTests {
    @Test
    func clearEmptiesTheTextAndNotifies() {
        let model = IslandSearchFieldTextModel(text: "query")
        let callbacks = IslandSearchFieldCallbacks()
        let field = IslandSearchField("Find", text: Bindable(model).text, onClear: { callbacks.clears += 1 })

        field.clear()

        #expect(model.text.isEmpty)
        #expect(callbacks.clears == 1)
    }

    @Test
    func clearWithoutACallbackOnlyEmptiesTheText() {
        let model = IslandSearchFieldTextModel(text: "query")
        let field = IslandSearchField("Find", text: Bindable(model).text)

        field.clear()

        #expect(model.text.isEmpty)
    }

    @Test
    func submitInvokesTheCallbackWhenPresent() {
        let model = IslandSearchFieldTextModel(text: "query")
        let callbacks = IslandSearchFieldCallbacks()
        IslandSearchField("Find", text: Bindable(model).text, onSubmit: { callbacks.submits += 1 }).submit()
        IslandSearchField("Find", text: Bindable(model).text).submit()

        #expect(callbacks.submits == 1)
        #expect(model.text == "query")
    }

    @Test
    func rendersTheClearButtonOnlyForNonEmptyTextWithInternalFocus() async throws {
        let model = IslandSearchFieldTextModel(text: "")
        let probe = IslandSearchFieldProbe()
        let hosted = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) {
            IslandSearchFieldInternalFocusHarness(model: model, probe: probe)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
        let empty = hosted.snapshot()

        model.text = "query"
        try await hosted.settle(.milliseconds(50))
        #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))

        probe.field?.requestFocus()
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
    }

    @Test
    func rendersWithAnExternalFocusBindingAndRequestsFocusThroughIt() async throws {
        let model = IslandSearchFieldTextModel(text: "query")
        let probe = IslandSearchFieldProbe()
        let hosted = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) {
            IslandSearchFieldExternalFocusHarness(model: model, probe: probe)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())

        probe.field?.requestFocus()
        try await hosted.settle(.milliseconds(50))
        #expect(hosted.renders())
    }
}
