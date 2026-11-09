//
//  SettingsSidebarFix.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/04/2023.
//

import AppKit

extension NSSplitViewItem {
    @objc fileprivate var canCollapseSwizzled: Bool {
        if let check = self.viewController.view.window?.isSettingsWindow, check {
            return false
        }
        return self.canCollapseSwizzled
    }

    static func swizzle() {
        exchange(#selector(getter: NSSplitViewItem.canCollapse), #selector(getter: canCollapseSwizzled))
    }

    static func exchange(_ origSelector: Selector, _ swizzledSelector: Selector) {
        let originalMethodSet = class_getInstanceMethod(self as AnyClass, origSelector)
        let swizzledMethodSet = class_getInstanceMethod(self as AnyClass, swizzledSelector)

        guard let originalMethodSet, let swizzledMethodSet else { return }
        method_exchangeImplementations(originalMethodSet, swizzledMethodSet)
    }
}
