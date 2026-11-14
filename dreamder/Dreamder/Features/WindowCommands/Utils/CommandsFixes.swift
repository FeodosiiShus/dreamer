//
//  CommandsFixes.swift
//  Dreamder
//
//  Created by Wouter Hennen on 11/03/2023.
//

import SwiftUI

extension EventModifiers {
    nonisolated static let hidden: EventModifiers = .numericPad
}

extension NSMenuItem {
    @MainActor
    @objc
    fileprivate func fixAlternate(_ newValue: NSEvent.ModifierFlags) {
        if newValue.contains(.numericPad) {
            isAlternate = true
            fixAlternate(newValue.subtracting(.numericPad))
        }

        fixAlternate(newValue)

        if self.title == "Open Recent" {
            FileCommands.recentProjectsMenu.attachMenu(to: self)
        }

        if self.title == "OpenWindowAction" || self.title.isEmpty {
            self.isHidden = true
            self.allowsKeyEquivalentWhenHidden = true
        }
    }

    static func swizzle() {
        let origSelector = #selector(setter: NSMenuItem.keyEquivalentModifierMask)
        let swizzledSelector = #selector(fixAlternate)
        let originalMethodSet = class_getInstanceMethod(self as AnyClass, origSelector)
        let swizzledMethodSet = class_getInstanceMethod(self as AnyClass, swizzledSelector)

        guard let originalMethodSet, let swizzledMethodSet else { return }
        method_exchangeImplementations(originalMethodSet, swizzledMethodSet)
    }
}
