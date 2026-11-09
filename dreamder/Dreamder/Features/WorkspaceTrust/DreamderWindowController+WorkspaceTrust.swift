import AppKit

extension DreamderWindowController {
    static let trustProjectCommandID = "trust_project"

    func registerTrustProjectCommand() {
        CommandManager.shared.addCommand(
            name: "Trust Project\u{2026}",
            title: "Trust Project\u{2026}",
            id: Self.trustProjectCommandID,
            command: { [weak self] in self?.trustProject(nil) }
        )
    }

    @IBAction func trustProject(_ sender: Any?) {
        Task { _ = await requestProjectTrust() }
    }

    func requestProjectTrust(using trust: WorkspaceTrust? = nil) async -> Bool {
        await (trust ?? workspaceTrust).requestTrust(for: workspace?.fileURL)
    }
}
