import Foundation

enum BranchesPopupRefAction: String, CaseIterable, Hashable, Identifiable {
    case checkout
    case newBranch
    case checkoutAndRebase
    case checkoutAndUpdate
    case compareWithCurrent
    case showWorkingTreeDiff
    case rebaseCurrentOnto
    case mergeIntoCurrent
    case newWorktree
    case update
    case push
    case trackedBranch
    case pullRebase
    case pullMerge
    case pushTag
    case rename
    case delete

    var id: String { rawValue }
}

struct BranchesPopupRefActionContext {
    let currentName: String
    let hasRemotes: Bool
    let isDetachedHead: Bool
    let trackedBranch: BranchesPopupRef?

    init(
        currentName: String,
        hasRemotes: Bool,
        isDetachedHead: Bool = false,
        trackedBranch: BranchesPopupRef? = nil
    ) {
        self.currentName = currentName
        self.hasRemotes = hasRemotes
        self.isDetachedHead = isDetachedHead
        self.trackedBranch = trackedBranch
    }
}

enum BranchesPopupRefActionEntry: Hashable {
    case action(BranchesPopupRefAction)
    case separator
}

enum BranchesPopupRefActions {
    static func entries(
        for ref: BranchesPopupRef,
        context: BranchesPopupRefActionContext,
        includeTrackedBranch: Bool = true
    ) -> [BranchesPopupRefActionEntry] {
        let blocks = actionBlocks(for: ref, context: context, includeTrackedBranch: includeTrackedBranch)
        var entries: [BranchesPopupRefActionEntry] = []
        for block in blocks where !block.isEmpty {
            if !entries.isEmpty {
                entries.append(.separator)
            }
            entries.append(contentsOf: block.map(BranchesPopupRefActionEntry.action))
        }
        return entries
    }

    static func actionBlocks(
        for ref: BranchesPopupRef,
        context: BranchesPopupRefActionContext,
        includeTrackedBranch: Bool = true
    ) -> [[BranchesPopupRefAction]] {
        let checkoutBlock: [BranchesPopupRefAction] = [.checkout, .newBranch, .checkoutAndRebase, .checkoutAndUpdate]
        let compareBlock: [BranchesPopupRefAction] = [.compareWithCurrent, .showWorkingTreeDiff]
        let integrateBlock: [BranchesPopupRefAction] = [.rebaseCurrentOnto, .mergeIntoCurrent]
        let worktreeBlock: [BranchesPopupRefAction] = [.newWorktree]
        let branchBlock: [BranchesPopupRefAction] = [.update, .push, .trackedBranch, .pullRebase, .pullMerge]
        let tagBlock: [BranchesPopupRefAction] = [.pushTag]
        let finalBlock: [BranchesPopupRefAction] = [.rename, .delete]

        return [
            checkoutBlock,
            compareBlock,
            integrateBlock,
            worktreeBlock,
            branchBlock,
            tagBlock,
            finalBlock
        ].map { block in
            block.filter { action in
                guard shows(action, ref: ref, context: context, includeTrackedBranch: includeTrackedBranch) else {
                    return false
                }
                return true
            }
        }
    }

    static func shows(
        _ action: BranchesPopupRefAction,
        ref: BranchesPopupRef,
        context: BranchesPopupRefActionContext,
        includeTrackedBranch: Bool = true
    ) -> Bool {
        let isBranch = ref.kind != .tag
        switch action {
        case .checkout:
            return !(ref.kind == .local && ref.isCurrent)
        case .newBranch:
            return isBranch
        case .checkoutAndRebase:
            return isBranch && !ref.isCurrent && !context.isDetachedHead
        case .checkoutAndUpdate:
            return ref.kind == .local && !ref.isCurrent && context.hasRemotes && ref.upstream != nil
        case .compareWithCurrent:
            return isBranch && !ref.isCurrent
        case .showWorkingTreeDiff:
            return true
        case .rebaseCurrentOnto:
            return isBranch && !ref.isCurrent && !context.isDetachedHead
        case .mergeIntoCurrent:
            return !ref.isCurrent
        case .newWorktree:
            return true
        case .update:
            return ref.kind == .local && context.hasRemotes && ref.upstream != nil
        case .push:
            return ref.kind == .local
        case .trackedBranch:
            return ref.kind == .local && context.trackedBranch != nil && includeTrackedBranch
        case .pullRebase, .pullMerge:
            return ref.kind == .remote
        case .pushTag:
            return ref.kind == .tag
        case .rename:
            return ref.kind == .local
        case .delete:
            return !ref.isCurrent
        }
    }

    static func title(
        for action: BranchesPopupRefAction,
        ref: BranchesPopupRef,
        context: BranchesPopupRefActionContext
    ) -> String {
        switch action {
        case .checkout:
            return "Checkout"
        case .newBranch:
            return "New Branch from '\(displayName(ref))'…"
        case .checkoutAndRebase:
            return "Checkout and Rebase onto '\(context.currentName)'"
        case .checkoutAndUpdate:
            return "Checkout and Update"
        case .compareWithCurrent:
            return "Compare with '\(context.currentName)'"
        case .showWorkingTreeDiff:
            return "Show Diff with Working Tree"
        case .rebaseCurrentOnto:
            return "Rebase '\(context.currentName)' onto '\(displayName(ref))'"
        case .mergeIntoCurrent:
            return "Merge '\(displayName(ref))' into '\(context.currentName)'"
        case .newWorktree:
            return "New Worktree from '\(displayName(ref))'…"
        case .update:
            return "Update"
        case .push:
            return "Push…"
        case .trackedBranch:
            return "Tracked Branch '\(context.trackedBranch?.shortName ?? "")'"
        case .pullRebase:
            return "Pull into '\(context.currentName)' Using Rebase"
        case .pullMerge:
            return "Pull into '\(context.currentName)' Using Merge"
        case .pushTag:
            return "Push Tag"
        case .rename:
            return "Rename…"
        case .delete:
            return "Delete"
        }
    }

    static func displayName(_ ref: BranchesPopupRef) -> String {
        ref.kind == .local ? ref.name : ref.shortName
    }
}
