import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CETaskCoverageTests {
    private func decodeTask(_ json: String) throws -> CETask {
        try JSONDecoder().decode(CETask.self, from: Data(json.utf8))
    }

    private func encodedObject(_ task: CETask) throws -> [String: Any] {
        let data = try JSONEncoder().encode(task)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test
    func targetInitializerOnlySetsTheTarget() {
        let task = CETask(target: "My Mac")

        #expect(task.target == "My Mac")
        #expect(task.name.isEmpty)
        #expect(task.command.isEmpty)
        #expect(task.workingDirectory.isEmpty)
        #expect(task.environmentVariables.isEmpty)
    }

    @Test
    func designatedInitializerAssignsEveryField() {
        let variable = CETask.EnvironmentVariable(key: "KEY", value: "VALUE")
        let task = CETask(
            name: "Build",
            target: "My Mac",
            workingDirectory: "/tmp",
            command: "make",
            environmentVariables: [variable]
        )

        #expect(task.name == "Build")
        #expect(task.target == "My Mac")
        #expect(task.workingDirectory == "/tmp")
        #expect(task.command == "make")
        #expect(task.environmentVariables == [variable])
    }

    @Test
    func environmentVariableInitializersAssignKeyAndValue() {
        let empty = CETask.EnvironmentVariable()
        let filled = CETask.EnvironmentVariable(key: "A", value: "B")

        #expect(empty.key.isEmpty)
        #expect(empty.value.isEmpty)
        #expect(filled.key == "A")
        #expect(filled.value == "B")
        #expect(empty.id != filled.id)
    }

    @Test
    func taskIsInvalidWithoutNameOrCommand() {
        #expect(CETask().isInvalid)
        #expect(CETask(name: "Build").isInvalid)
        #expect(CETask(command: "make").isInvalid)
        #expect(!CETask(name: "Build", command: "make").isInvalid)
    }

    @Test
    func fullCommandWithoutWorkingDirectoryIsTheCommand() {
        let task = CETask(name: "Build", command: "make all")

        #expect(task.fullCommand == "make all")
    }

    @Test
    func fullCommandChangesIntoTheQuotedWorkingDirectoryFirst() {
        let task = CETask(name: "Build", workingDirectory: "/tmp/my project", command: "make all")

        #expect(task.fullCommand == "cd \"/tmp/my project\" && make all")
    }

    @Test
    func fullCommandEscapesQuotesInTheWorkingDirectory() {
        let task = CETask(name: "Build", workingDirectory: "/tmp/a\"b", command: "ls")

        #expect(task.fullCommand == "cd \"/tmp/a\\\"b\" && ls")
    }

    @Test
    func environmentVariablesDictionaryKeepsTheLastValueOfADuplicatedKey() {
        let task = CETask(
            name: "Build",
            command: "make",
            environmentVariables: [
                CETask.EnvironmentVariable(key: "A", value: "1"),
                CETask.EnvironmentVariable(key: "B", value: "2"),
                CETask.EnvironmentVariable(key: "A", value: "3")
            ]
        )

        #expect(task.environmentVariablesDictionary == ["A": "3", "B": "2"])
        #expect(CETask().environmentVariablesDictionary.isEmpty)
    }

    @Test
    func encodingOmitsEmptyFieldsAndTheDefaultTarget() throws {
        let task = CETask(name: "Build", target: "My Mac", command: "make")

        let object = try encodedObject(task)

        #expect(Set(object.keys) == ["name", "command"])
    }

    @Test
    func encodingOmitsEveryEmptyFieldOfAnEmptyTask() throws {
        let object = try encodedObject(CETask())

        #expect(object.isEmpty)
    }

    @Test
    func encodingWritesTargetWorkingDirectoryAndEnvironmentDictionary() throws {
        let task = CETask(
            name: "Build",
            target: "Simulator",
            workingDirectory: "/work",
            command: "make",
            environmentVariables: [
                CETask.EnvironmentVariable(key: "A", value: "1"),
                CETask.EnvironmentVariable(key: "B", value: "2")
            ]
        )

        let object = try encodedObject(task)

        #expect(object["name"] as? String == "Build")
        #expect(object["target"] as? String == "Simulator")
        #expect(object["workingDirectory"] as? String == "/work")
        #expect(object["command"] as? String == "make")
        #expect(object["environmentVariables"] as? [String: String] == ["A": "1", "B": "2"])
    }

    @Test
    func codableRoundTripPreservesTheFieldsAndTheIdentity() throws {
        let task = CETask(
            name: "Build",
            target: "Simulator",
            workingDirectory: "/work",
            command: "make",
            environmentVariables: [CETask.EnvironmentVariable(key: "A", value: "1")]
        )

        let decoded = try JSONDecoder().decode(CETask.self, from: JSONEncoder().encode(task))

        #expect(decoded.name == task.name)
        #expect(decoded.target == task.target)
        #expect(decoded.workingDirectory == task.workingDirectory)
        #expect(decoded.command == task.command)
        #expect(decoded.environmentVariablesDictionary == task.environmentVariablesDictionary)
        #expect(decoded.id == task.id)
    }

    @Test
    func decodingAppliesDefaultsForOptionalKeys() throws {
        let task = try decodeTask(#"{"name":"Build","command":"make"}"#)

        #expect(task.target.isEmpty)
        #expect(task.workingDirectory.isEmpty)
        #expect(task.environmentVariables.isEmpty)
    }

    @Test
    func decodingReadsEveryKey() throws {
        let task = try decodeTask(
            #"{"name":"Build","target":"T","workingDirectory":"/w","command":"make","environmentVariables":{"K":"V"}}"#
        )

        #expect(task.target == "T")
        #expect(task.workingDirectory == "/w")
        #expect(task.environmentVariables.map(\.key) == ["K"])
        #expect(task.environmentVariables.map(\.value) == ["V"])
    }

    @Test
    func decodingRequiresNameAndCommand() {
        #expect(throws: DecodingError.self) { try decodeTask(#"{"command":"make"}"#) }
        #expect(throws: DecodingError.self) { try decodeTask(#"{"name":"Build"}"#) }
    }

    @Test
    func equalityAndHashingCoverEveryField() {
        let first = CETask(name: "A", target: "T", workingDirectory: "/w", command: "c")
        let second = CETask(name: "A", target: "T", workingDirectory: "/w", command: "c")

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)

        second.name = "B"
        #expect(first != second)
        second.name = "A"
        second.target = "U"
        #expect(first != second)
        second.target = "T"
        second.workingDirectory = "/x"
        #expect(first != second)
        second.workingDirectory = "/w"
        second.command = "d"
        #expect(first != second)
        second.command = "c"
        second.environmentVariables = [CETask.EnvironmentVariable(key: "K", value: "V")]
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    @Test
    func tasksWithTheSameSourceAndNameAreTheSameTaskAndOthersAreNot() {
        #expect(CETask(name: "A", command: "c") == CETask(name: "A", command: "c"))
        #expect(CETask(name: "A", command: "c") != CETask(name: "B", command: "c"))
        #expect(CETask(name: "A", command: "c") != CETask(name: "A", command: "c", source: "npm:."))
    }
}
