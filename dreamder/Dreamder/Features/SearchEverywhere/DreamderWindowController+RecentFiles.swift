import AppKit

extension DreamderWindowController {
    @IBAction func openRecentFiles(_ sender: Any?) {
        SearchEverywherePanelHost.shared.openRecentFiles(in: self)
    }
}
