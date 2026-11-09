//
//  FindCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct FindCommands: Commands {

    @FirstResponder var responder

    static let selector = #selector(NSTextView.performFindPanelAction(_:))

    var hasResponder: Bool {
        responder?.responds(to: Self.selector) ?? false
    }

    var body: some Commands {
        CommandMenu("Find") {
            Group {
                FindButtons(responder: responder)
            }
            .disabled(!hasResponder)
        }
    }
}

extension FindCommands {
    struct FindButtons: View {
        let responder: NSResponder?
        var jumpTarget: Any?

        var body: some View {
            Button("Find...") {
                send(.showFindPanel)
            }
            .keymapShortcut(.find)

            Button("Find and Replace...") {
                send(tag: Self.findAndReplaceTag)
            }
            .keymapShortcut(.findAndReplace)

            Button("Find Next") {
                send(.next)
            }
            .keymapShortcut(.findNext)

            Button("Find Previous") {
                send(.previous)
            }
            .keymapShortcut(.findPrevious)

            Button("Use Selection for Find") {
                send(.setFindString)
            }
            .keymapShortcut(.useSelectionForFind)

            Button("Jump to Selection") {
                NSApp.sendAction(#selector(NSTextView.centerSelectionInVisibleArea(_:)), to: jumpTarget, from: nil)
            }
            .keymapShortcut(.jumpToSelection)
        }

        static let findAndReplaceTag = 12

        func send(_ action: NSFindPanelAction) {
            send(tag: Int(action.rawValue))
        }

        func send(tag: Int) {
            let item = NSMenuItem()
            item.tag = tag
            responder?.perform(FindCommands.selector, with: item)
        }
    }
}
