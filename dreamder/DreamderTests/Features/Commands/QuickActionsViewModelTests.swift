import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class QuickActionsRunLog {
    var entries: [String] = []
}

@MainActor
struct QuickActionsRegistration {
    let token: String
    let log: QuickActionsRunLog
    let ids: [String]

    init(names: [String]) {
        let token = UUID().uuidString
        let log = QuickActionsRunLog()
        self.token = token
        self.log = log
        self.ids = names.map { name in
            let id = "quick-\(token)-\(name)"
            CommandManager.shared.addCommand(name: id, title: "Quick \(token) \(name)", id: id) {
                log.entries.append(id)
            }
            return id
        }
    }

    func title(_ name: String) -> String {
        "Quick \(token) \(name)"
    }
}

@MainActor
@Suite(.uiGate)
struct QuickActionsViewModelTests {
    @Test
    func emptyQueryListsEveryRegisteredCommand() {
        let registration = QuickActionsRegistration(names: ["Alpha", "Beta"])
        let model = QuickActionsViewModel()

        model.fetchMatchingCommands(val: "")

        #expect(Set(model.filteredCommands.map(\.id)).isSuperset(of: registration.ids))
    }

    @Test
    func queryFiltersByTitleIgnoringCase() {
        let registration = QuickActionsRegistration(names: ["Alpha", "Beta"])
        let model = QuickActionsViewModel()

        model.fetchMatchingCommands(val: "\(registration.token) alpha".lowercased())
        #expect(model.filteredCommands.map(\.id) == [registration.ids[0]])

        model.fetchMatchingCommands(val: registration.token)
        #expect(Set(model.filteredCommands.map(\.id)) == Set(registration.ids))
    }

    @Test
    func queryWithoutMatchesYieldsNoCommands() {
        let model = QuickActionsViewModel()

        model.fetchMatchingCommands(val: "no-such-command-\(UUID().uuidString)")

        #expect(model.filteredCommands.isEmpty)
    }

    @Test
    func resetClearsTheQueryAndListsEveryCommandAgain() {
        let registration = QuickActionsRegistration(names: ["Alpha"])
        let model = QuickActionsViewModel()
        model.commandQuery = "something"
        model.filteredCommands = []

        model.reset()

        #expect(model.commandQuery.isEmpty)
        #expect(model.filteredCommands.map(\.id).contains(registration.ids[0]))
    }

    @Test
    func showAllCommandsKeepsTheQuery() {
        let registration = QuickActionsRegistration(names: ["Alpha"])
        let model = QuickActionsViewModel()
        model.commandQuery = "kept"

        model.showAllCommands()

        #expect(model.commandQuery == "kept")
        #expect(model.filteredCommands.map(\.id).contains(registration.ids[0]))
    }

    @Test
    func runningACommandExecutesItAndClearsTheState() throws {
        let registration = QuickActionsRegistration(names: ["Alpha"])
        let model = QuickActionsViewModel()
        model.fetchMatchingCommands(val: registration.token)
        model.commandQuery = registration.token
        let command = try #require(model.filteredCommands.first)

        model.run(command)

        #expect(registration.log.entries == [registration.ids[0]])
        #expect(model.commandQuery.isEmpty)
        #expect(model.filteredCommands.isEmpty)
    }

    @Test
    func highlightEmphasizesTheMatchedRangeIgnoringCase() throws {
        let model = QuickActionsViewModel()
        model.commandQuery = "BET"

        let highlighted = model.highlight("Alphabet")

        #expect(highlighted.string == "Alphabet")
        var matchedRange = NSRange(location: 0, length: 0)
        let font = try #require(highlighted.attribute(.font, at: 5, effectiveRange: &matchedRange) as? NSFont)
        #expect(matchedRange == NSRange(location: 5, length: 3))
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        let color = try #require(highlighted.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor)
        #expect(color == NSColor.labelColor)
        #expect(highlighted.attribute(.font, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func highlightLeavesTheTitleUntouchedWithoutAMatch() {
        let model = QuickActionsViewModel()

        model.commandQuery = "zzz"
        let unmatched = model.highlight("Alphabet")
        model.commandQuery = ""
        let empty = model.highlight("Alphabet")

        for title in [unmatched, empty] {
            #expect(title.string == "Alphabet")
            var range = NSRange(location: 0, length: 0)
            #expect(title.attributes(at: 0, effectiveRange: &range).isEmpty)
            #expect(range == NSRange(location: 0, length: 8))
        }
    }
}
