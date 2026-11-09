import AppKit
import Foundation

@MainActor
@Observable
final class MergeRevisionsViewModel {
    let path: String

    private(set) var merge: ThreeWayMerge?
    private(set) var context: MergeConflictContext?
    private(set) var leftPane = MergePaneContent.empty
    private(set) var rightPane = MergePaneContent.empty
    private(set) var resultPane = MergePaneContent.empty
    private(set) var contentRevision = 0
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var isConflictValid = true
    private(set) var errorMessage: String?
    private(set) var isResultEdited = false
    private(set) var isUndecodable = false
    var resultText = ""

    private let manager: SourceControlManager
    private let repository: MergeConflictRepository
    @ObservationIgnored private var entry: MergeConflictEntry?
    @ObservationIgnored private var revisionSet: MergeConflictRepository.RevisionSet?

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

    var summary: String {
        guard let merge else { return isLoading ? "Computing differences…" : "" }
        if merge.isFullyResolved {
            return "All conflicts resolved"
        }
        return merge.summary
    }

    var canApply: Bool { merge != nil && isConflictValid && !isSaving && !isLoading }

    var canAcceptSide: Bool { isConflictValid && !isSaving && !isLoading && (merge != nil || isUndecodable) }

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

        let entries: [MergeConflictEntry]
        do {
            entries = try await repository.entries()
        } catch {
            isLoading = false
            errorMessage = MergeToolErrorText.describeStatusFailure(error)
            return
        }
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
        isUndecodable = revisions.isNotUTF8
        if revisions.isBinary {
            isLoading = false
            errorMessage = "Binary files cannot be merged manually"
            return
        }
        if revisions.isNotUTF8 {
            isLoading = false
            errorMessage = "This file is not valid UTF-8 and cannot be merged here. "
                + "Use Accept Left or Accept Right to take one side with Git."
            return
        }

        let ours = context.swapsSides ? revisions.theirs.text : revisions.ours.text
        let theirs = context.swapsSides ? revisions.ours.text : revisions.theirs.text
        let computed = ThreeWayMerge(base: revisions.base.text, ours: ours, theirs: theirs)
        merge = computed
        refreshContent(merge: computed)
        isLoading = false
    }

    private func resolve(_ blockID: Int, with resolution: ThreeWayMerge.Resolution) {
        guard var updated = merge else { return }
        updated.resolve(blockID, with: resolution)
        merge = updated
        refreshContent(merge: updated)
    }

    private func applyNonConflicting(_ mode: ThreeWayMerge.NonConflictingMode) {
        guard var updated = merge else { return }
        updated.applyNonConflicting(mode)
        merge = updated
        refreshContent(merge: updated)
    }

    func userEditedResult(_ text: String) {
        let converted = lineEnding.converting(text)
        resultText = converted
        if converted != merge?.resultText {
            isResultEdited = true
        }
    }

    func requestResolve(
        _ blockID: Int,
        with resolution: ThreeWayMerge.Resolution,
        window: NSWindow?
    ) async {
        guard await confirmReplacingManualEdits(window: window) else { return }
        resolve(blockID, with: resolution)
    }

    func requestApplyNonConflicting(_ mode: ThreeWayMerge.NonConflictingMode, window: NSWindow?) async {
        guard await confirmReplacingManualEdits(window: window) else { return }
        applyNonConflicting(mode)
    }

    private func confirmReplacingManualEdits(window: NSWindow?) async -> Bool {
        guard isResultEdited else { return true }
        return await MergeToolConfirmation.ask(
            window: window,
            title: "Discard Manual Edits?",
            message: "The result was edited by hand. This change is generated from the conflict blocks "
                + "and replaces your edits.",
            confirmTitle: "Discard Edits and Apply",
            cancelTitle: "Keep Editing"
        )
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
        guard let entry, let context, let revisionSet, canAcceptSide else { return false }
        if let merge, !isUndecodable, !isSideMissing(choice, in: revisionSet, swapsSides: context.swapsSides) {
            resultText = choice == .yours ? merge.leftText : merge.rightText
            return await apply()
        }
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

    private func isSideMissing(
        _ choice: MergeSideChoice,
        in revisionSet: MergeConflictRepository.RevisionSet,
        swapsSides swaps: Bool
    ) -> Bool {
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

    private var lineEnding: LineEnding { merge?.lineEnding ?? .lineFeed }

    private func refreshContent(merge: ThreeWayMerge) {
        leftPane = merge.leftPane
        rightPane = merge.rightPane
        resultPane = merge.resultPane
        resultText = merge.resultText
        isResultEdited = false
        contentRevision += 1
    }
}
