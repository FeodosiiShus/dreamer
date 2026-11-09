import Foundation
import OrderedCollections

extension Editor {
    var pinnedTabCount: Int {
        tabs.count(where: { isPinned($0.file) })
    }

    func isPinned(_ file: CEWorkspaceFile) -> Bool {
        pinnedURLs.contains(file.url)
    }

    var unpinnedFiles: [CEWorkspaceFile] {
        tabs.map(\.file).filter { !isPinned($0) }
    }

    func setPinned(_ pinned: Bool, file: CEWorkspaceFile) {
        guard let tab = tabs.first(where: { $0.file == file }), isPinned(tab.file) != pinned else { return }
        var ordered = Array(tabs).filter { $0 != tab }
        if pinned {
            pinnedURLs.insert(tab.file.url)
            if temporaryTab == tab {
                temporaryTab = nil
            }
        } else {
            pinnedURLs.remove(tab.file.url)
        }
        let boundary = ordered.count(where: { isPinned($0.file) })
        ordered.insert(tab, at: boundary)
        tabs = OrderedSet(ordered)
    }

    func togglePinned(file: CEWorkspaceFile) {
        setPinned(!isPinned(file), file: file)
    }

    func closeUnpinnedTabs(where isIncluded: (CEWorkspaceFile) -> Bool = { _ in true }) {
        closeTabsInSequence(ArraySlice(unpinnedFiles.filter(isIncluded)))
    }

    private func closeTabsInSequence(_ files: ArraySlice<CEWorkspaceFile>) {
        guard let file = files.first else { return }
        closeTab(file: file) { [weak self] closed in
            guard closed else { return }
            self?.closeTabsInSequence(files.dropFirst())
        }
    }
}
