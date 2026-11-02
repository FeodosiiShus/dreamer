import AppKit

extension Notification.Name {
    static let showGitBranchesPopup = Notification.Name("dev.dreamder.showGitBranchesPopup")
}

extension DreamderWindowController {
    @IBAction func showGitBranches(_ sender: Any?) {
        NotificationCenter.default.post(name: .showGitBranchesPopup, object: workspace)
    }
}
