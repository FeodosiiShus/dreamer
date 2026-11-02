import AppKit

final class BranchesPopupMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ sender: Any?) {
        handler()
    }
}

enum BranchesPopupMenuFactory {
    static func menu(
        for ref: BranchesPopupRef,
        model: BranchesPopupViewModel,
        includeTrackedBranch: Bool = true
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let context = model.refActionContext(for: ref)
        let entries = BranchesPopupRefActions.entries(
            for: ref,
            context: context,
            includeTrackedBranch: includeTrackedBranch
        )
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let action):
                let title = BranchesPopupRefActions.title(for: action, ref: ref, context: context)
                menu.addItem(menuItem(for: action, title: title, ref: ref, model: model, context: context))
            }
        }
        return menu
    }

    private static func menuItem(
        for action: BranchesPopupRefAction,
        title: String,
        ref: BranchesPopupRef,
        model: BranchesPopupViewModel,
        context: BranchesPopupRefActionContext
    ) -> NSMenuItem {
        switch action {
        case .checkout:
            return item(title) { model.checkout(ref) }
        case .newBranch:
            return item(title) { model.promptNewBranch(from: ref) }
        case .checkoutAndRebase:
            return item(title) { model.checkoutAndRebase(ref) }
        case .checkoutAndUpdate:
            return item(title) { model.checkoutAndUpdate(ref) }
        case .compareWithCurrent:
            return item(title) { model.compareWithCurrent(ref) }
        case .showWorkingTreeDiff:
            return item(title) { model.showWorkingTreeDiff(ref) }
        case .rebaseCurrentOnto:
            return item(title) { model.rebaseCurrent(onto: ref) }
        case .mergeIntoCurrent:
            return item(title) { model.merge(ref) }
        case .newWorktree:
            return item(title) { model.promptNewWorktree(from: ref) }
        case .update:
            return item(title) { model.update(ref) }
        case .push:
            return item(title, keyEquivalent: "k", modifiers: [.command, .shift]) { model.push(ref) }
        case .trackedBranch:
            return trackedBranchItem(title: title, ref: ref, model: model, context: context)
        case .pullRebase:
            return item(title) { model.pull(ref, rebase: true) }
        case .pullMerge:
            return item(title) { model.pull(ref, rebase: false) }
        case .pushTag:
            return pushTagItem(title: title, ref: ref, model: model)
        case .rename:
            return item(title) { model.promptRename(ref) }
        case .delete:
            return item(title) { model.delete(ref) }
        }
    }

    private static func trackedBranchItem(
        title: String,
        ref: BranchesPopupRef,
        model: BranchesPopupViewModel,
        context: BranchesPopupRefActionContext
    ) -> NSMenuItem {
        let trackedItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        guard let trackedRef = context.trackedBranch else { return trackedItem }
        let submenu = menu(for: trackedRef, model: model, includeTrackedBranch: false)
        trackedItem.submenu = submenu
        return trackedItem
    }

    private static func pushTagItem(
        title: String,
        ref: BranchesPopupRef,
        model: BranchesPopupViewModel
    ) -> NSMenuItem {
        let tagItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for remote in model.remoteNames {
            submenu.addItem(item("Push to \(remote)") { model.pushTag(ref, remote: remote) })
        }
        tagItem.submenu = submenu
        return tagItem
    }

    private static func item(
        _ title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let action = BranchesPopupMenuAction(handler)
        let menuItem = NSMenuItem(
            title: title,
            action: #selector(BranchesPopupMenuAction.invoke(_:)),
            keyEquivalent: keyEquivalent
        )
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = action
        menuItem.representedObject = action
        menuItem.isEnabled = true
        return menuItem
    }
}
