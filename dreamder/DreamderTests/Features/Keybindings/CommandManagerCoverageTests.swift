import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommandManagerCoverageTests {
    @Test
    func addedCommandsAreListedAndExecutedByIdentifier() {
        let manager = CommandManager.shared
        let id = "coverage-\(UUID().uuidString)"
        var runs = 0

        manager.addCommand(name: id, title: "Coverage command", id: id) { runs += 1 }
        manager.executeCommand(id)
        manager.executeCommand(id)

        let listed = manager.commands.first { $0.id == id }
        #expect(listed?.title == "Coverage command")
        #expect(runs == 2)
    }

    @Test
    func executingAnUnknownCommandDoesNothing() {
        CommandManager.shared.executeCommand("missing-\(UUID().uuidString)")
    }

    @Test
    func addingTwiceUnderTheSameIdentifierReplacesTheCommand() {
        let manager = CommandManager.shared
        let id = "replace-\(UUID().uuidString)"
        var log: [String] = []

        manager.addCommand(name: id, title: "First", id: id) { log.append("first") }
        manager.addCommand(name: id, title: "Second", id: id) { log.append("second") }
        manager.executeCommand(id)

        #expect(log == ["second"])
        #expect(manager.commands.filter { $0.id == id }.map(\.title) == ["Second"])
    }

    @Test
    func commandsAreIdentifiedAndHashedByIdentifierOnly() {
        let first = Command(id: "same", title: "One", closureWrapper: {})
        let second = Command(id: "same", title: "Two", closureWrapper: {})
        let other = Command(id: "other", title: "One", closureWrapper: {})

        #expect(first == second)
        #expect(first != other)
        #expect(Set([first, second, other]).count == 2)
        #expect((first < other) == false)
    }
}
