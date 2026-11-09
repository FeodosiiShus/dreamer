import Testing
@testable import Dreamder

struct SearchPanelTestItem: Identifiable, Hashable {
    let id: Int
}

@MainActor
private final class SearchPanelRecorder {
    var clicked: [SearchPanelTestItem] = []
    var beeps = 0
}

@MainActor
@Suite(.uiGate)
struct SearchPanelModelTests {
    private static let first = SearchPanelTestItem(id: 1)
    private static let second = SearchPanelTestItem(id: 2)
    private static let third = SearchPanelTestItem(id: 3)
    private static let items = [first, second, third]

    private func makeModel(
        recorder: SearchPanelRecorder = SearchPanelRecorder()
    ) -> SearchPanelModel<SearchPanelTestItem> {
        SearchPanelModel(
            onRowClick: { recorder.clicked.append($0) },
            beep: { recorder.beeps += 1 }
        )
    }

    @Test
    func updateSelectsTheFirstOptionAndClearsTheSelectionWithoutOptions() {
        let model = makeModel()

        model.update(options: Self.items)
        #expect(model.options == Self.items)
        #expect(model.selection == Self.first)

        model.selection = Self.third
        model.update(options: [Self.second, Self.third])
        #expect(model.selection == Self.second)

        model.update(options: [])
        #expect(model.options.isEmpty)
        #expect(model.selection == nil)
    }

    @Test
    func submitClicksTheSelectedRowAndBeepsWithoutSelection() {
        let recorder = SearchPanelRecorder()
        let model = makeModel(recorder: recorder)

        model.submit()
        #expect(recorder.clicked.isEmpty)
        #expect(recorder.beeps == 1)

        model.update(options: Self.items)
        model.moveDown()
        model.submit()
        #expect(recorder.clicked == [Self.second])
        #expect(recorder.beeps == 1)
    }

    @Test
    func defaultFeedbackNeverClicksARow() {
        let recorder = SearchPanelRecorder()
        let model = SearchPanelModel<SearchPanelTestItem>(onRowClick: { recorder.clicked.append($0) })

        model.submit()

        #expect(recorder.clicked.isEmpty)
    }

    @Test
    func moveDownAdvancesAndStopsAtTheLastOption() {
        let model = makeModel()
        model.update(options: Self.items)

        model.moveDown()
        #expect(model.selection == Self.second)
        model.moveDown()
        #expect(model.selection == Self.third)
        model.moveDown()
        #expect(model.selection == Self.third)
    }

    @Test
    func moveUpRetreatsAndStopsAtTheFirstOption() {
        let model = makeModel()
        model.update(options: Self.items)
        model.selection = Self.third

        model.moveUp()
        #expect(model.selection == Self.second)
        model.moveUp()
        #expect(model.selection == Self.first)
        model.moveUp()
        #expect(model.selection == Self.first)
    }

    @Test
    func movingWithoutASelectionOrWithAStaleOneSelectsTheFirstOption() {
        let model = makeModel()
        model.update(options: Self.items)
        let stale = SearchPanelTestItem(id: 99)

        model.selection = nil
        model.moveUp()
        #expect(model.selection == Self.first)

        model.selection = nil
        model.moveDown()
        #expect(model.selection == Self.first)

        model.selection = stale
        model.moveUp()
        #expect(model.selection == Self.first)

        model.selection = stale
        model.moveDown()
        #expect(model.selection == Self.first)
    }

    @Test
    func movingWithoutOptionsKeepsTheSelectionEmpty() {
        let model = makeModel()

        model.moveUp()
        model.moveDown()

        #expect(model.selection == nil)
    }

    @Test
    func togglePreviewFlipsVisibility() {
        let model = makeModel()
        #expect(model.previewVisible)

        model.togglePreview()
        #expect(model.previewVisible == false)

        model.togglePreview()
        #expect(model.previewVisible)
    }
}
