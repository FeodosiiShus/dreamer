//
//  TerminalEmulatorView+Coordinator.swift
//  DreamderModules/TerminalEmulator
//
//  Created by Lukas Pistrol on 24.03.22.
//

import SwiftUI
import SwiftTerm

extension TerminalEmulatorView {
    final class Coordinator: NSObject, CELocalShellTerminalViewDelegate {
        private let terminalID: UUID
        public var onTitleChange: ((_ title: String) -> Void)?

        var mode: TerminalMode
        var appliedAppearance: TerminalAppearance?

        init(terminalID: UUID, mode: TerminalMode, onTitleChange: ((_ title: String) -> Void)?) {
            self.terminalID = terminalID
            self.onTitleChange = onTitleChange
            self.mode = mode
            super.init()
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func sizeChanged(source: CETerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: CETerminalView, title: String) {
            onTitleChange?(title)
        }

        func processTerminated(source: TerminalView, exit: ProcessExit?) {
            guard let exit else {
                return
            }
            if case .shell = mode {
                source.feed(text: "\(exit.summary)\n\r\n")
                source.feed(text: "To open a new session, create a new terminal tab.")
                TerminalCache.shared.removeCachedView(terminalID)
            }
        }
    }
}
