import Foundation

extension GitClient {
    func commitToolWindow(message: String, amend: Bool) async throws {
        var command = amend ? "commit --amend" : "commit"
        command += " --message=\(Self.commitToolWindowQuote(message))"
        _ = try await run(command)
    }

    static func commitToolWindowQuote(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }
}
