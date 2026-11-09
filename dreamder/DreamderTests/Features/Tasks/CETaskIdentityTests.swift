import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CETaskIdentityTests {
    private func decodeTask(_ json: String) throws -> CETask {
        try JSONDecoder().decode(CETask.self, from: Data(json.utf8))
    }

    @Test
    func decodingTheSameTaskTwiceYieldsTheSameIdentity() throws {
        let json = #"{"name":"Build","command":"make"}"#

        let first = try decodeTask(json)
        let second = try decodeTask(json)

        #expect(first.id == second.id)
        #expect(first.id == CETask.stableID(source: CETask.workspaceSource, name: "Build"))
    }

    @Test
    func identitySurvivesAnEncodeDecodeRoundTrip() throws {
        let task = CETask(name: "Serve", target: "My Mac", workingDirectory: "web", command: "npm start")

        let decoded = try JSONDecoder().decode(CETask.self, from: JSONEncoder().encode(task))

        #expect(decoded.id == task.id)
        #expect(decoded == task)
    }

    @Test
    func taskWithEnvironmentVariablesEqualsItsRoundTrip() throws {
        let task = CETask(
            name: "Serve",
            command: "npm start",
            environmentVariables: [
                CETask.EnvironmentVariable(key: "PORT", value: "80"),
                CETask.EnvironmentVariable(key: "HOST", value: "localhost")
            ]
        )

        let decoded = try JSONDecoder().decode(CETask.self, from: JSONEncoder().encode(task))

        #expect(decoded == task)
        #expect(decoded.hashValue == task.hashValue)
    }

    @Test
    func defaultTargetIsEqualToTheOmittedTarget() throws {
        let explicit = CETask(name: "Serve", target: CETask.defaultTarget, command: "npm start")
        let omitted = CETask(name: "Serve", command: "npm start")
        let other = CETask(name: "Serve", target: "SSH", command: "npm start")

        #expect(explicit == omitted)
        #expect(explicit.hashValue == omitted.hashValue)
        #expect(explicit != other)
    }

    @Test
    func identityIsNotWrittenToTheSettingsFile() throws {
        let task = CETask(name: "Build", command: "make")

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any]
        )

        #expect(object.keys.sorted() == ["command", "name"])
    }

    @Test
    func savedWorkspaceSettingsWithoutIdentitiesKeepTheirTaskIdentitiesAcrossLaunches() throws {
        let json = #"""
        {"tasks":[{"name":"Build","command":"make"},{"name":"Test","command":"make test","workingDirectory":"core"}]}
        """#

        let firstLaunch = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data(json.utf8))
        let secondLaunch = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data(json.utf8))

        #expect(firstLaunch.tasks.map(\.id) == secondLaunch.tasks.map(\.id))
        #expect(Set(firstLaunch.tasks.map(\.id)).count == 2)
    }

    @Test
    func identityDependsOnSourceAndName() {
        let base = CETask.stableID(source: "workspace", name: "Build")

        #expect(base == CETask.stableID(source: "workspace", name: "Build"))
        #expect(base != CETask.stableID(source: "workspace", name: "Test"))
        #expect(base != CETask.stableID(source: "npm:", name: "Build"))
        #expect(CETask.stableID(source: "a", name: "bc") != CETask.stableID(source: "ab", name: "c"))
    }

    @Test
    func identityIsAVersion5Uuid() {
        let text = CETask.stableID(source: "workspace", name: "Build").uuidString
        let characters = Array(text)

        #expect(characters[14] == "5")
        #expect(["8", "9", "A", "B"].contains(characters[19]))
    }

    @Test
    func renamingATaskAfterItsIdentityWasReadKeepsTheIdentity() {
        let task = CETask(name: "Build", command: "make")
        let before = task.id

        task.name = "Compile"

        #expect(task.id == before)
        #expect(CETask(name: "Compile", command: "make").id != before)
    }

    @Test
    func renamingATaskBeforeItsIdentityWasReadDerivesItFromTheNewName() {
        let task = CETask(name: "Build", command: "make")

        task.name = "Compile"

        #expect(task.id == CETask.stableID(source: CETask.workspaceSource, name: "Compile"))
    }

    @Test
    func unnamedDraftsGetDistinctIdentitiesThatStickOnceTheyAreNamed() {
        let first = CETask(target: "My Mac")
        let second = CETask(target: "My Mac")

        #expect(first.id != second.id)

        let firstID = first.id
        first.name = "Named"
        #expect(first.id == firstID)
    }

    @Test
    func discoveredTasksCarryTheirSourceInTheIdentity() {
        let user = CETask(name: "npm run dev", command: "npm run dev")
        let discovered = CETask(name: "npm run dev", command: "npm run dev", source: "npm:")

        #expect(user.id != discovered.id)
        #expect(discovered.source == "npm:")
        #expect(user.source == CETask.workspaceSource)
    }
}
