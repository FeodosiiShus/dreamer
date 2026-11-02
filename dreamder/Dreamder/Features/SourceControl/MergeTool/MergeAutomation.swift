import AppKit
import Foundation

@MainActor
enum MergeAutomation {
    static let notification = Notification.Name("dev.dreamder.merge")

    private static var queue: Task<Void, Never> = Task {}
    private static var targetPath = ""
    private static var bannerPath: String?
    private static var bannerAction: (() -> Void)?

    static func registerBanner(path: String?, action: (() -> Void)?) {
        bannerPath = path
        bannerAction = action
    }

    static func install() {
        DistributedNotificationCenter.default().addObserver(
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

    private static func enqueue(_ command: String) {
        let previous = queue
        queue = Task { @MainActor in
            await previous.value
            await perform(command)
        }
    }

    private static func perform(_ command: String) async {
        let parts = command.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init)
        guard let name = parts.first, !name.isEmpty else { return }
        let first = parts.count > 1 ? parts[1] : ""
        let second = parts.count > 2 ? parts[2] : ""

        switch name {
        case "target":
            targetPath = first
        case "conflicts":
            if let workspace = workspace(for: first.isEmpty ? targetPath : first) {
                MergeToolPresenter.showConflicts(workspace: workspace)
                await MergeToolPresenter.conflictsModel(for: workspace)?.reload()
            }
        case "select":
            MergeToolPresenter.conflictsModel?.select(first)
        case "selectAdd":
            MergeToolPresenter.conflictsModel?.select(first, toggling: true)
        case "selectRange":
            MergeToolPresenter.conflictsModel?.select(first, extending: true)
        case "acceptYours":
            await MergeToolPresenter.conflictsModel?.accept(.yours)
        case "acceptTheirs":
            await MergeToolPresenter.conflictsModel?.accept(.theirs)
        case "mergeSelected":
            MergeToolPresenter.conflictsModel?.openMergeWindow()
        case "mergeFile":
            if let workspace = workspace(for: targetPath), !first.isEmpty {
                MergeToolPresenter.showMergeRevisions(workspace: workspace, path: first)
            }
        case "resolve":
            guard let model = MergeToolPresenter.revisionsModel,
                  let blockID = Int(first) else { return }
            let resolution: ThreeWayMerge.Resolution
            switch second {
            case "left": resolution = .left
            case "right": resolution = .right
            case "ignored": resolution = .ignored
            default: return
            }
            model.resolve(blockID, with: resolution)
        case "clickChip":
            let all = command.split(separator: ":").map(String.init)
            guard all.count == 4, let blockID = Int(all[2]) else { return }
            clickChip(pane: all[1], blockID: blockID, action: all[3])
        case "applyNonConflicting":
            guard let model = MergeToolPresenter.revisionsModel else { return }
            switch first {
            case "left": model.applyNonConflicting(.left)
            case "all": model.applyNonConflicting(.all)
            case "right": model.applyNonConflicting(.right)
            default: return
            }
        case "editResult":
            MergeToolPresenter.revisionsModel?.userEditedResult(unescaped(first))
        case "acceptLeft":
            closeRevisionsIfNeeded(await MergeToolPresenter.revisionsModel?.requestAcceptSide(.yours, window: nil))
        case "acceptRight":
            closeRevisionsIfNeeded(await MergeToolPresenter.revisionsModel?.requestAcceptSide(.theirs, window: nil))
        case "apply":
            closeRevisionsIfNeeded(await MergeToolPresenter.revisionsModel?.requestApply(window: nil))
        case "cancel":
            closeRevisionsIfNeeded(await MergeToolPresenter.revisionsModel?.requestCancel(window: nil))
        case "closeRevisions":
            MergeToolPresenter.revisionsWindow?.performClose(nil)
        case "closeConflicts":
            MergeToolPresenter.conflictsWindow?.performClose(nil)
        case "bannerResolve":
            bannerAction?()
        case "focusWorkspace":
            if let workspace = workspace(for: first.isEmpty ? targetPath : first),
               let window = workspace.windowControllers.first?.window {
                window.makeKeyAndOrderFront(nil)
            }
        case "menuResolve":
            if let item = gitMenuItem("Resolve Conflicts"), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        case "confirm":
            MergeToolConfirmation.automationAnswer = first == "yes"
        case "dump":
            writeDump(to: first)
        default:
            return
        }
    }

    private static func closeRevisionsIfNeeded(_ finished: Bool?) {
        guard finished == true else { return }
        MergeToolPresenter.revisionsWindow?.performClose(nil)
    }

    private static func gitMenuItem(_ titlePrefix: String) -> NSMenuItem? {
        guard let gitMenu = NSApp.mainMenu?.items.first(where: { $0.title == "Git" })?.submenu else {
            return nil
        }
        return gitMenu.items.first { $0.title.hasPrefix(titlePrefix) }
    }

    private static func clickChip(pane: String, blockID: Int, action: String) {
        guard let window = MergeToolPresenter.revisionsWindow,
              let textView = findTextView(in: window.contentView, identifier: "merge-pane-\(pane)"),
              let storage = textView.textStorage,
              let target = NSURL(string: "merge-block://\(action)/\(blockID)") else { return }
        var location: Int?
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let url = value as? NSURL, url == target {
                location = range.location
                stop.pointee = true
            }
        }
        guard let location else { return }
        textView.clicked(onLink: target, at: location)
    }

    private static func findTextView(in view: NSView?, identifier: String) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.identifier?.rawValue == identifier {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    private static func workspace(for path: String) -> WorkspaceDocument? {
        let documents = NSDocumentController.shared.documents.compactMap { $0 as? WorkspaceDocument }
        if !path.isEmpty {
            let target = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
            if let match = documents.first(where: {
                $0.sourceControlManager?.workspaceURL.standardizedFileURL.path(percentEncoded: false) == target
            }) {
                return match
            }
        }
        if let controller = NSApp.keyWindow?.windowController as? DreamderWindowController,
           let workspace = controller.workspace {
            return workspace
        }
        return documents.first
    }

    private static func writeDump(to directoryPath: String) {
        let directory = URL(fileURLWithPath: directoryPath.isEmpty ? NSTemporaryDirectory() : directoryPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("merge.txt")

        var lines: [String] = []
        let target = workspace(for: targetPath)
        if let target {
            lines.append("workspace=\(target.sourceControlManager?.workspaceURL.path(percentEncoded: false) ?? "")")
        }
        lines.append("target=\(targetPath)")
        lines.append("documents=\(NSDocumentController.shared.documents.compactMap { ($0 as? WorkspaceDocument)?.sourceControlManager?.workspaceURL.path(percentEncoded: false) }.joined(separator: ","))")
        lines.append("windowTitles=\(NSApp.windows.map(\.title).joined(separator: "|"))")
        lines.append("menu.resolvePresent=\(gitMenuItem("Resolve Conflicts") == nil ? 0 : 1)")
        lines.append("menu.resolveEnabled=\(gitMenuItem("Resolve Conflicts")?.isEnabled == true ? 1 : 0)")
        lines.append("menu.resolveTitle=\(gitMenuItem("Resolve Conflicts")?.title ?? "")")
        lines.append("banner.path=\(bannerPath ?? "")")
        lines.append("banner.action=\(bannerAction == nil ? 0 : 1)")

        let conflictsModel = target.flatMap { MergeToolPresenter.conflictsModel(for: $0) }
            ?? MergeToolPresenter.conflictsModel
        lines.append("conflicts.open=\(conflictsModel == nil ? 0 : 1)")
        if let model = conflictsModel {
            lines.append("conflicts.summary=\(escaped(model.summary))")
            lines.append("conflicts.error=\(escaped(model.errorMessage ?? ""))")
            lines.append("conflicts.busy=\(model.isBusy ? 1 : 0)")
            lines.append("conflicts.primary=\(model.primaryPath ?? "")")
            lines.append("conflicts.selected=\(model.selectedPaths.sorted().joined(separator: ","))")
            lines.append("conflicts.count=\(model.entries.count)")
            for entry in model.entries {
                lines.append("conflicts.entry=\(entry.path)|\(model.detail(for: entry, choice: .yours))"
                             + "|\(model.detail(for: entry, choice: .theirs))")
            }
            lines.append("conflicts.yoursHeader=\(model.yoursHeader)")
            lines.append("conflicts.theirsHeader=\(model.theirsHeader)")
        }

        let revisionsModel = MergeToolPresenter.revisionsModel
        lines.append("revisions.open=\(revisionsModel == nil ? 0 : 1)")
        if let model = revisionsModel {
            lines.append("revisions.path=\(model.path)")
            lines.append("revisions.title=\(escaped(model.title))")
            lines.append("revisions.summary=\(escaped(model.summary))")
            lines.append("revisions.error=\(escaped(model.errorMessage ?? ""))")
            lines.append("revisions.valid=\(model.isConflictValid ? 1 : 0)")
            lines.append("revisions.edited=\(model.isResultEdited ? 1 : 0)")
            lines.append("revisions.loading=\(model.isLoading ? 1 : 0)")
            lines.append("revisions.leftTitle=\(escaped(model.leftTitle))")
            lines.append("revisions.rightTitle=\(escaped(model.rightTitle))")
            if let merge = model.merge {
                lines.append("revisions.conflicts=\(merge.conflictCount)")
                lines.append("revisions.changes=\(merge.changeCount)")
                for block in merge.blocks {
                    lines.append("revisions.block=\(block.id)|\(block.kind)|\(block.resolution)"
                                 + "|\(block.baseRange.lowerBound)-\(block.baseRange.upperBound)")
                }
            }
            lines.append("revisions.nonConflictingLeft=\(model.hasNonConflictingChanges(.left) ? 1 : 0)")
            lines.append("revisions.nonConflictingAll=\(model.hasNonConflictingChanges(.all) ? 1 : 0)")
            lines.append("revisions.nonConflictingRight=\(model.hasNonConflictingChanges(.right) ? 1 : 0)")
            lines.append("revisions.result=\(escaped(model.resultText))")
            lines.append("revisions.left=\(escaped(model.leftPane.text))")
            lines.append("revisions.right=\(escaped(model.rightPane.text))")
        }

        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func unescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
