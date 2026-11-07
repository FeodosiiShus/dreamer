import Foundation

nonisolated extension GitClient {
    func commitToolWindow(message: String, amend: Bool) async throws {
        var arguments = ["commit"]
        if amend {
            arguments.append("--amend")
        }
        arguments.append(contentsOf: ["--message", message])
        _ = try await run(arguments: arguments)
    }
}
