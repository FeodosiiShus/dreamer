import Foundation

nonisolated extension GitClient {
    static let tagExistsMessage = "The tag with the same name exists."

    func createTag(
        name: String,
        at revision: String,
        message: String? = nil,
        force: Bool = false
    ) async throws {
        try Self.requireRefNames(name, revision)
        guard try await isValidTagName(name) else {
            throw GitClientError.outputError("'\(name)' is not a valid tag name.")
        }
        if !force, try await tagExists(name) {
            throw GitClientError.outputError(Self.tagExistsMessage)
        }
        var arguments = ["tag"]
        if force {
            arguments.append("-f")
        }
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedMessage.isEmpty {
            arguments += ["-a", "-m", trimmedMessage]
        }
        arguments += ["--end-of-options", name, revision]
        _ = try await run(arguments: arguments)
    }

    func isValidTagName(_ name: String) async throws -> Bool {
        let result = try await runResult(arguments: ["check-ref-format", "refs/tags/\(name)"])
        return result.success
    }

    func tagExists(_ name: String) async throws -> Bool {
        let result = try await runResult(arguments: ["rev-parse", "-q", "--verify", "refs/tags/\(name)"])
        guard result.success(ignoring: [1]) else {
            throw Self.error(for: result)
        }
        return !result.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
