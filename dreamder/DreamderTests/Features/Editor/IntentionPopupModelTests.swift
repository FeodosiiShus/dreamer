import AppKit
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
enum IntentionPopupFixtures {
    static func action(
        _ title: String,
        category: IntentionCategory = .quickFix,
        preferred: Bool = false
    ) -> IntentionAction {
        IntentionAction(
            id: "\(category.rawValue).\(title)",
            title: title,
            category: category,
            isPreferred: preferred,
            payload: .command(Command(title: title, command: "run.\(title)"))
        )
    }

    static func group(
        _ title: String,
        category: IntentionCategory = .quickFix,
        actions: [IntentionAction]
    ) -> IntentionGroup {
        IntentionGroup(id: "\(category.rawValue).\(title)", category: category, title: title, actions: actions)
    }

    static var sampleGroups: [IntentionGroup] {
        [
            group("Cannot find 'x' in scope", actions: [action("Declare x"), action("Import x")]),
            group("Refactorings", category: .refactoring, actions: [action("Extract", category: .refactoring)]),
            group("Source Actions", category: .source, actions: [action("Organize", category: .source)])
        ]
    }

    static func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

@MainActor
@Suite(.uiGate)
struct IntentionPopupModelTests {
    @Test
    func groupsFlattenIntoHeadersFollowedByTheirActions() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)

        #expect(model.rows.count == 7)
        #expect(model.rows[0] == .header(id: "0.Cannot find 'x' in scope", title: "Cannot find 'x' in scope"))
        #expect(model.rows[1].intention?.title == "Declare x")
        #expect(model.rows[2].intention?.title == "Import x")
        #expect(model.rows[3].intention == nil)
        #expect(model.rows[4].intention?.title == "Extract")
        #expect(model.rows[5].intention == nil)
        #expect(model.rows[6].intention?.title == "Organize")
        #expect(Set(model.rows.map(\.id)).count == 7)
        #expect(!model.isMessage)
        #expect(model.message == nil)
        #expect(model.panelWidth == IntentionPopupModel.listWidth)
    }

    @Test
    func emptyGroupsProduceNoRows() {
        let empty = IntentionPopupFixtures.group("Empty", actions: [])
        let model = IntentionPopupModel(groups: [empty])

        #expect(model.rows.isEmpty)
        #expect(model.selectedAction == nil)
        model.moveSelection(1)
        model.activate()
        #expect(model.selectedIndex == 0)
    }

    @Test
    func initialSelectionIsTheFirstActionNotTheHeader() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)

        #expect(model.selectedIndex == 1)
        #expect(model.selectedAction?.title == "Declare x")
    }

    @Test
    func initialSelectionPrefersTheFirstPreferredAction() {
        let groups = [
            IntentionPopupFixtures.group("A", actions: [IntentionPopupFixtures.action("One")]),
            IntentionPopupFixtures.group(
                "B",
                category: .refactoring,
                actions: [
                    IntentionPopupFixtures.action("Two", category: .refactoring),
                    IntentionPopupFixtures.action("Best", category: .refactoring, preferred: true)
                ]
            )
        ]
        let model = IntentionPopupModel(groups: groups)

        #expect(model.selectedAction?.title == "Best")
        #expect(model.selectedIndex == 4)
    }

    @Test
    func selectionSkipsHeadersAndWrapsAround() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)

        model.moveSelection(1)
        #expect(model.selectedAction?.title == "Import x")
        model.moveSelection(1)
        #expect(model.selectedAction?.title == "Extract")
        model.moveSelection(1)
        #expect(model.selectedAction?.title == "Organize")
        model.moveSelection(1)
        #expect(model.selectedAction?.title == "Declare x")
        model.moveSelection(-1)
        #expect(model.selectedAction?.title == "Organize")
    }

    @Test
    func selectIgnoresHeadersAndOutOfRangeIndexes() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)

        model.select(3)
        #expect(model.selectedIndex == 1)
        model.select(99)
        #expect(model.selectedIndex == 1)
        model.select(-1)
        #expect(model.selectedIndex == 1)
        model.select(4)
        #expect(model.selectedAction?.title == "Extract")
    }

    @Test
    func keyEventsMoveApplyAndClose() throws {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)
        var applied: [String] = []
        var closed = 0
        model.onApply = { applied.append($0.title) }
        model.dismiss = { closed += 1 }

        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(126)))
        #expect(model.selectedAction?.title == "Organize")
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(125)))
        #expect(model.selectedAction?.title == "Declare x")
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(36)))
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(76)))
        #expect(applied == ["Declare x", "Declare x"])
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(125, flags: .command)) == false)
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(0)) == false)
        #expect(model.handle(event: try IntentionPopupFixtures.keyEvent(53)))
        #expect(closed == 1)
    }

    @Test
    func messageVariantHasNoRowsAndItsOwnSize() {
        let model = IntentionPopupModel(message: "Nothing here")
        var applied = 0
        model.onApply = { _ in applied += 1 }

        #expect(model.isMessage)
        #expect(model.message == "Nothing here")
        #expect(model.rows.isEmpty)
        #expect(model.panelWidth == IntentionPopupModel.messageWidth)
        #expect(model.preferredHeight == IntentionPopupModel.messageHeight)
        model.activate()
        #expect(applied == 0)
    }

    @Test
    func preferredHeightSumsRowHeightsAndIsCapped() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)
        let expected = 3 * IntentionPopupModel.headerRowHeight
            + 4 * IntentionPopupModel.actionRowHeight
            + 2 * IntentionPopupModel.listPadding
        #expect(model.preferredHeight == expected)

        let many = (0..<40).map { IntentionPopupFixtures.action("Fix \($0)") }
        let tall = IntentionPopupModel(groups: [IntentionPopupFixtures.group("Many", actions: many)])
        #expect(tall.preferredHeight == IntentionPopupModel.maximumHeight)
    }

    @Test
    func categoriesMapToBulbIcons() {
        #expect(IntentionCategory.quickFix.bulbIconName == "codeInsight/quickfixBulb")
        #expect(IntentionCategory.refactoring.bulbIconName == "actions/refactoringBulb")
        #expect(IntentionCategory.source.bulbIconName == nil)
        #expect(IntelliJIcon.nsImage("codeInsight/quickfixBulb") != nil)
        #expect(IntelliJIcon.nsImage("actions/refactoringBulb") != nil)
    }
}
