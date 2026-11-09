//
//  StatusBarCursorPositionLabel.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI
import CodeEditSourceEditor

struct StatusBarCursorPositionLabel: View {
    @Environment(EditorManager.self) private var editorManager

    private var tab: EditorInstance? {
        editorManager.activeEditor.selectedTab
    }

    var body: some View {
        Group {
            if let currentTab = tab {
                LineLabel(editorInstance: currentTab)
            } else {
                Text("").accessibilityLabel("No Selection")
            }
        }
        .statusBarWidgetFrame()
        .fixedSize()
        .accessibilityIdentifier("CursorPositionLabel")
        .accessibilityAddTraits(.updatesFrequently)
        .onHover(perform: hoverChanged)
    }

    func hoverChanged(_ active: Bool) {
        isHovering(active)
    }

    struct LineLabel: View {
        @Environment(\.modifierKeys)
        private var modifierKeys

        let editorInstance: EditorInstance

        private var cursorPositions: [CursorPosition] {
            editorInstance.cursorPositions
        }

        init(editorInstance: EditorInstance) {
            self.editorInstance = editorInstance
        }

        var body: some View {
            StatusBarWidgetText(
                text: Self.label(
                    for: cursorPositions,
                    modifierKeys: ShortcutModifiers(modifierKeys).eventModifiers,
                    lineCount: getLines
                )
            )
        }

        /// Finds the lines contained by a range in the currently selected document.
        /// - Parameter range: The range to query.
        /// - Returns: The number of lines in the range.
        func getLines(_ range: NSRange) -> Int {
            return editorInstance.rangeTranslator.linesInRange(range)
        }

        /// Create a label string for cursor positions.
        /// - Returns: A string describing the user's location in a document.
        static func label(
            for cursorPositions: [CursorPosition],
            modifierKeys: EventModifiers,
            lineCount linesInRange: (NSRange) -> Int
        ) -> String {
            if cursorPositions.isEmpty {
                return ""
            }

            // More than one selection, display the number of selections.
            if cursorPositions.count > 1 {
                return "\(cursorPositions.count) selections"
            }

            // If the selection is more than just a cursor, return the length.
            if cursorPositions[0].range.length > 0 {
                // When the option key is pressed display the character range.
                if modifierKeys.contains(.option) {
                    return "Char: \(cursorPositions[0].range.location) Len: \(cursorPositions[0].range.length)"
                }

                let lineCount = linesInRange(cursorPositions[0].range)

                if lineCount > 1 {
                    return "\(lineCount) lines"
                }

                return "\(cursorPositions[0].range.length) characters"
            }

            // When the option key is pressed display the character offset.
            if modifierKeys.contains(.option) {
                return "Char: \(cursorPositions[0].range.location) Len: 0"
            }

            // When there's a single cursor, display the line and column.
            let start = cursorPositions[0].start
            guard start.line > 0, start.column > 0 else {
                return ""
            }
            return "\(start.line):\(start.column)"
        }
    }
}
