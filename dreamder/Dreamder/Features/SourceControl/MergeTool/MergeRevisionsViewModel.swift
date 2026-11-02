import AppKit
import Combine
import Foundation

@MainActor
final class MergeRevisionsViewModel: ObservableObject {
    let path: String

    @Published private(set) var merge: ThreeWayMerge?
    @Published private(set) var context: MergeConflictContext?
    @Published private(set) var leftPane = MergePaneContent.empty
    @Published private(set) var rightPane = MergePaneContent.empty
    @Published private(set) var resultPane = MergePaneContent.empty
    @Published private(set) var contentRevision = 0
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isConflictValid = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var isResultEdited = false
    @Published var resultText = ""

    private let manager: SourceControlManager
    private let repository: MergeConflictRepository
    private var entry: MergeConflictEntry?
    private var revisionSet: MergeConflictRepository.RevisionSet?

    init?(workspace: WorkspaceDocument, path: String, autoLoad: Bool = true) {
        guard let manager = workspace.sourceControlManager,
              let repository = MergeConflictRepository(workspace: workspace),
              !path.isEmpty else {
            return nil
        }
        self.manager = manager
        self.repository = repository
        self.path = path
        guard autoLoad else { return }
        Task { [weak self] in
            await self?.load()
        }
    }

    var title: String { "Merge Revisions for \(path)" }

    var leftTitle: String {
        switch context?.operation {
        case .merge:
            return "Your version, branch \(context?.yoursLabel ?? "")"
        case .rebase:
            return "Your commits, branch \(context?.yoursLabel ?? "")"
        case .cherryPick, .stash:
            return "Local changes"
        default:
            return "Yours"
        }
    }

    var rightTitle: String {
        switch context?.operation {
        case .merge:
            return "Theirs, branch \(context?.theirsLabel ?? "")"
        case .rebase:
            return "Changes from branch \(context?.theirsLabel ?? "")"
        case .cherryPick:
            return "Changes from \(context?.theirsLabel ?? "")"
        case .stash:
            return "Changes from stash"
        default:
            return "Theirs"
        }
    }

    var summary: String {
        guard let merge else { return isLoading ? "Computing differences…" : "" }
        if merge.isFullyResolved {
            return "All conflicts resolved"
        }
        return merge.summary
    }

    var canApply: Bool { merge != nil && isConflictValid && !isSaving && !isLoading }

    var canAcceptSide: Bool { isConflictValid && !isSaving && !isLoading && merge != nil }

    var hasUnresolvedConflicts: Bool { (merge?.conflictCount ?? 0) > 0 }

    func hasNonConflictingChanges(_ mode: ThreeWayMerge.NonConflictingMode) -> Bool {
        merge?.hasApplicableNonConflictingChanges(mode) ?? false
    }

    func canApplyNonConflicting(_ mode: ThreeWayMerge.NonConflictingMode) -> Bool {
        !isLoading && !isSaving && hasNonConflictingChanges(mode)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let context = await repository.context()
        self.context = context

        let entries = await repository.entries()
        entry = entries.first { $0.path == path }
        guard entry != nil else {
            isConflictValid = false
            isLoading = false
            errorMessage = "Conflict is not valid and no longer can be resolved."
            return
        }
        isConflictValid = true

        let revisions = await repository.revisions(for: path)
        revisionSet = revisions
        if revisions.isBinary {
            isLoading = false
            errorMessage = "Binary files cannot be merged manually"
            return
        }

        let ours = context.swapsSides ? revisions.theirs.text : revisions.ours.text
        let theirs = context.swapsSides ? revisions.ours.text : revisions.theirs.text
        merge = ThreeWayMerge(base: revisions.base.text, ours: ours, theirs: theirs)
        refreshContent()
        isLoading = false
    }

    func resolve(_ blockID: Int, with resolution: ThreeWayMerge.Resolution) {
        guard var updated = merge else { return }
        updated.resolve(blockID, with: resolution)
        merge = updated
        refreshContent()
    }

    func applyNonConflicting(_ mode: ThreeWayMerge.NonConflictingMode) {
        guard var updated = merge else { return }
        updated.applyNonConflicting(mode)
        merge = updated
        refreshContent()
    }

    func userEditedResult(_ text: String) {
        resultText = text
        if text != merge?.resultText {
            isResultEdited = true
        }
    }

    func requestApply(window: NSWindow?) async -> Bool {
        guard canApply else { return false }
        if hasUnresolvedConflicts {
            let confirmed = await MergeToolConfirmation.ask(
                window: window,
                title: "Unprocessed Changes",
                message: "Not every conflict is resolved. Save the current result and mark the file as resolved?",
                confirmTitle: "Save Current Result",
                cancelTitle: "Back to Resolving"
            )
            guard confirmed else { return false }
        }
        return await apply()
    }

    func requestAcceptSide(_ choice: MergeSideChoice, window: NSWindow?) async -> Bool {
        guard canAcceptSide else { return false }
        if isResultEdited {
            let name = choice == .yours ? "Accept Left" : "Accept Right"
            let confirmed = await MergeToolConfirmation.ask(
                window: window,
                title: "Discard Changes?",
                message: "The result has unsaved changes that will be lost.",
                confirmTitle: "Discard Changes and \(name)",
                cancelTitle: "Continue Merge"
            )
            guard confirmed else { return false }
        }
        return await acceptSide(choice)
    }

    func requestCancel(window: NSWindow?) async -> Bool {
        guard isResultEdited else { return true }
        let confirmed = await MergeToolConfirmation.ask(
            window: window,
            title: "Discard Changes?",
            message: "The result has unsaved changes that will be lost.",
            confirmTitle: "Discard Changes",
            cancelTitle: "Continue Merge"
        )
        if confirmed {
            isResultEdited = false
        }
        return confirmed
    }

    func apply() async -> Bool {
        guard merge != nil, canApply else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.stageResult(resultText, path: path)
            isResultEdited = false
            await MergeConflictsCenter.shared.refresh(manager: manager)
            return true
        } catch {
            errorMessage = MergeToolErrorText.describe(error)
            return false
        }
    }

    func acceptSide(_ choice: MergeSideChoice) async -> Bool {
        guard let merge, canAcceptSide else { return false }
        if isSideMissing(choice) {
            guard let entry, let context else { return false }
            isSaving = true
            defer { isSaving = false }
            do {
                try await repository.accept(choice, entry: entry, context: context)
                await MergeConflictsCenter.shared.refresh(manager: manager)
                return true
            } catch {
                errorMessage = MergeToolErrorText.describe(error)
                return false
            }
        }
        resultText = choice == .yours ? merge.leftText : merge.rightText
        return await apply()
    }

    private func isSideMissing(_ choice: MergeSideChoice) -> Bool {
        guard let revisionSet else { return false }
        let swaps = context?.swapsSides ?? false
        let content: MergeConflictRepository.StageContent
        switch choice {
        case .yours:
            content = swaps ? revisionSet.theirs : revisionSet.ours
        case .theirs:
            content = swaps ? revisionSet.ours : revisionSet.theirs
        }
        if case .missing = content {
            return true
        }
        return false
    }

    private func refreshContent() {
        guard let merge else { return }
        leftPane = merge.leftPane
        rightPane = merge.rightPane
        resultPane = merge.resultPane
        resultText = merge.resultText
        isResultEdited = false
        contentRevision += 1
    }
}
