import AppKit
import Foundation

@MainActor
enum MergeAutomation {
    static let notification = Notification.Name("dev.dreamder.merge")

    private(set) static var queue: Task<Void, Never> = Task {}
    private(set) static var targetPath = ""
    private(set) static var revisionsPath: String?
    private(set) static var pendingAnswer: Bool?
    private(set) static var bannerPath: String?
    private(set) static var bannerAction: (() -> Void)?

    private struct Invocation {
        let command: String
        let name: String
        let first: String
        let second: String
    }

    static func registerBanner(path: String?, action: (() -> Void)?) {
        bannerPath = path
        bannerAction = action
    }

    static func install(center: NotificationCenter = DistributedNotificationCenter.default()) {
        center.addObserver(
            forName: notification,
            object: nil,
            queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated {
                enqueue(command)
            }
        }
    }

    static func enqueue(_ command: String) {
        let previous = queue
        queue = Task { @MainActor in
            await previous.value
            await perform(command)
        }
    }

    static func perform(_ command: String, mainMenu: NSMenu? = NSApp.mainMenu) async {
        let parts = command.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init)
        guard let name = parts.first, !name.isEmpty else { return }
        let invocation = Invocation(
            command: command,
            name: name,
            first: parts.count > 1 ? parts[1] : "",
            second: parts.count > 2 ? parts[2] : ""
        )
        if name == "confirm" {
            pendingAnswer = invocation.first == "yes"
            return
        }
        guard let answer = pendingAnswer else {
            await execute(invocation, mainMenu: mainMenu)
            return
        }
        pendingAnswer = nil
        await MergeToolConfirmation.$override.withValue(answer) {
            await execute(invocation, mainMenu: mainMenu)
        }
    }

    private static func execute(_ invocation: Invocation, mainMenu: NSMenu?) async {
        let first = invocation.first

        switch invocation.name {
        case "target":
            targetPath = first
            revisionsPath = nil
        case "conflicts":
            if let workspace = commandWorkspace(path: first) {
                adoptTarget(workspace)
                MergeToolPresenter.showConflicts(workspace: workspace)
                await MergeToolPresenter.conflictsModel(for: workspace)?.reload()
            }
        case "select":
            targetConflictsModel?.select(first)
        case "selectAdd":
            targetConflictsModel?.select(first, toggling: true)
        case "selectRange":
            targetConflictsModel?.select(first, extending: true)
        case "acceptYours":
            await targetConflictsModel?.accept(.yours)
        case "acceptTheirs":
            await targetConflictsModel?.accept(.theirs)
        case "mergeSelected":
            targetConflictsModel?.openMergeWindow()
        case "mergeFile":
            if let workspace = openingWorkspace(), !first.isEmpty {
                adoptTarget(workspace)
                revisionsPath = first
                MergeToolPresenter.showMergeRevisions(workspace: workspace, path: first)
            }
        case "resolve":
            await resolveBlock(blockID: first, side: invocation.second)
        case "clickChip":
            let all = invocation.command.split(separator: ":").map(String.init)
            guard all.count == 4, let blockID = Int(all[2]) else { return }
            clickChip(pane: all[1], blockID: blockID, action: all[3])
        case "applyNonConflicting":
            await applyNonConflicting(mode: first)
        case "editResult":
            let text = String(invocation.command.dropFirst(invocation.name.count + 1))
            targetRevisionsModel?.userEditedResult(unescaped(text))
        case "acceptLeft":
            closeRevisionsIfNeeded(await targetRevisionsModel?.requestAcceptSide(.yours, window: nil))
        case "acceptRight":
            closeRevisionsIfNeeded(await targetRevisionsModel?.requestAcceptSide(.theirs, window: nil))
        case "apply":
            closeRevisionsIfNeeded(await targetRevisionsModel?.requestApply(window: nil))
        case "cancel":
            closeRevisionsIfNeeded(await targetRevisionsModel?.requestCancel(window: nil))
        case "closeRevisions":
            targetRevisionsWindow?.performClose(nil)
        case "closeConflicts":
            targetConflictsWindow?.performClose(nil)
        case "bannerResolve":
            bannerAction?()
        case "focusWorkspace":
            if let workspace = commandWorkspace(path: first),
               let window = workspace.windowControllers.first?.window {
                window.makeKeyAndOrderFront(nil)
            }
        case "menuResolve":
            if let item = gitMenuItem("Resolve Conflicts", in: mainMenu), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        case "dump":
            writeDump(to: first, mainMenu: mainMenu)
        default:
            return
        }
    }

    private static func adoptTarget(_ workspace: WorkspaceDocument) {
        guard targetPath.isEmpty, let manager = workspace.sourceControlManager else { return }
        targetPath = manager.workspaceURL.path(percentEncoded: false)
    }

    private static func closeRevisionsIfNeeded(_ finished: Bool?) {
        guard finished == true else { return }
        targetRevisionsWindow?.performClose(nil)
    }

    static func gitMenuItem(_ titlePrefix: String, in menu: NSMenu?) -> NSMenuItem? {
        guard let gitMenu = menu?.items.first(where: { $0.title == "Git" })?.submenu else {
            return nil
        }
        return gitMenu.items.first { $0.title.hasPrefix(titlePrefix) }
    }

    static func workspace(for path: String, keyWindow: NSWindow? = NSApp.keyWindow) -> WorkspaceDocument? {
        if !path.isEmpty, let match = exactWorkspace(at: path) {
            return match
        }
        if let controller = keyWindow?.windowController as? DreamderWindowController,
           let workspace = controller.workspace {
            return workspace
        }
        return NSDocumentController.shared.documents.lazy.compactMap { $0 as? WorkspaceDocument }.first
    }

    private static func unescaped(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingBackslash = false
        for scalar in value.unicodeScalars {
            guard pendingBackslash else {
                if scalar == "\\" {
                    pendingBackslash = true
                } else {
                    result.append(scalar)
                }
                continue
            }
            pendingBackslash = false
            switch scalar {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "\\": result.append("\\")
            default:
                result.append("\\")
                result.append(scalar)
            }
        }
        if pendingBackslash {
            result.append("\\")
        }
        return String(result)
    }
}
