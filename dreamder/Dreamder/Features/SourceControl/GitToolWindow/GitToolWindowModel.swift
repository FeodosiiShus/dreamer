import Observation
import SwiftUI

@Observable
@MainActor
final class GitToolWindowModel {
    enum Pane: Equatable {
        case log
        case console
        case shelf
    }

    let logModel: GitLogViewModel
    let shelfModel: ShelfModel
    private(set) var pane = Pane.log
    var branchesWidth: CGFloat = 210
    var detailsWidth: CGFloat = 320

    init(logModel: GitLogViewModel = GitLogViewModel(), shelfModel: ShelfModel = ShelfModel()) {
        self.logModel = logModel
        self.shelfModel = shelfModel
    }

    var showsConsole: Bool {
        pane == .console
    }

    var consoleSelection: Binding<Bool> {
        Binding(get: { self.showsConsole }, set: { self.setConsoleSelected($0) })
    }

    func showLog() {
        pane = .log
    }

    func showShelf() {
        pane = .shelf
    }

    func setConsoleSelected(_ selected: Bool) {
        if selected {
            pane = .console
        } else if pane == .console {
            pane = .log
        }
    }

    func refresh(manager: SourceControlManager) async {
        await manager.refreshBranches()
        await manager.refreshCurrentBranch()
        await logModel.load(manager: manager)
    }
}
