import AppKit
import Foundation

extension MergeAutomation {
    static func writeDump(to directoryPath: String, mainMenu: NSMenu?) {
        let directory = URL(fileURLWithPath: directoryPath.isEmpty ? NSTemporaryDirectory() : directoryPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("merge.txt")
        let lines = headerDumpLines(mainMenu: mainMenu)
            + conflictsDumpLines(targetConflictsModel)
            + revisionsDumpLines(targetRevisionsModel)
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func headerDumpLines(mainMenu: NSMenu?) -> [String] {
        var lines: [String] = []
        if let manager = targetWorkspace()?.sourceControlManager {
            lines.append("workspace=\(manager.workspaceURL.path(percentEncoded: false))")
        }
        lines.append("target=\(targetPath)")
        let documentPaths = NSDocumentController.shared.documents.compactMap {
            ($0 as? WorkspaceDocument)?.sourceControlManager?.workspaceURL.path(percentEncoded: false)
        }
        lines.append("documents=\(documentPaths.joined(separator: ","))")
        lines.append("windowTitles=\(NSApp.windows.map(\.title).joined(separator: "|"))")
        let resolveItem = gitMenuItem("Resolve Conflicts", in: mainMenu)
        lines.append("menu.resolvePresent=\(flag(resolveItem != nil))")
        lines.append("menu.resolveEnabled=\(flag(resolveItem?.isEnabled == true))")
        lines.append("menu.resolveTitle=\(resolveItem?.title ?? "")")
        lines.append("banner.path=\(bannerPath ?? "")")
        lines.append("banner.action=\(flag(bannerAction != nil))")
        return lines
    }

    private static func conflictsDumpLines(_ model: MergeConflictsViewModel?) -> [String] {
        var lines = ["conflicts.open=\(flag(model != nil))"]
        guard let model else { return lines }
        lines.append("conflicts.summary=\(escaped(model.summary))")
        lines.append("conflicts.error=\(escaped(model.errorMessage ?? ""))")
        lines.append("conflicts.busy=\(flag(model.isBusy))")
        lines.append("conflicts.primary=\(model.primaryPath ?? "")")
        lines.append("conflicts.selected=\(model.selectedPaths.sorted().joined(separator: ","))")
        lines.append("conflicts.count=\(model.entries.count)")
        for entry in model.entries {
            lines.append("conflicts.entry=\(entry.path)|\(model.detail(for: entry, choice: .yours))"
                         + "|\(model.detail(for: entry, choice: .theirs))")
        }
        lines.append("conflicts.yoursHeader=\(model.yoursHeader)")
        lines.append("conflicts.theirsHeader=\(model.theirsHeader)")
        return lines
    }

    private static func revisionsDumpLines(_ model: MergeRevisionsViewModel?) -> [String] {
        var lines = ["revisions.open=\(flag(model != nil))"]
        guard let model else { return lines }
        lines.append("revisions.path=\(model.path)")
        lines.append("revisions.title=\(escaped(model.title))")
        lines.append("revisions.summary=\(escaped(model.summary))")
        lines.append("revisions.error=\(escaped(model.errorMessage ?? ""))")
        lines.append("revisions.valid=\(flag(model.isConflictValid))")
        lines.append("revisions.edited=\(flag(model.isResultEdited))")
        lines.append("revisions.loading=\(flag(model.isLoading))")
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
        lines.append("revisions.nonConflictingLeft=\(flag(model.hasNonConflictingChanges(.left)))")
        lines.append("revisions.nonConflictingAll=\(flag(model.hasNonConflictingChanges(.all)))")
        lines.append("revisions.nonConflictingRight=\(flag(model.hasNonConflictingChanges(.right)))")
        lines.append("revisions.result=\(escaped(model.resultText))")
        lines.append("revisions.left=\(escaped(model.leftPane.text))")
        lines.append("revisions.right=\(escaped(model.rightPane.text))")
        return lines
    }

    private static func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
