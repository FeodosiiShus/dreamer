//
//  DreamderWindowController+Panels.swift
//  Dreamder
//
//  Created by Simon Kudsk on 11/05/2025.
//

import SwiftUI

extension DreamderWindowController {
    @objc
    func objcToggleFirstPanel() {
        toggleFirstPanel()
    }

    func toggleFirstPanel() {
        toggleToolWindow(.project)
    }

    @objc
    func objcToggleLastPanel() {
        toggleLastPanel()
    }

    func toggleLastPanel() {
        guard let manager = workspace?.toolWindowManager else { return }

        if let bottom = manager.active(.bottom) {
            manager.hide(bottom.anchor)
        } else {
            manager.show(.terminal)
        }
    }

    func toggleLeftPanel() {
        guard let manager = workspace?.toolWindowManager else { return }

        if manager.active(.left) != nil {
            manager.hide(.left)
        } else {
            manager.show(.project)
        }
    }

    func toggleToolWindow(_ id: ToolWindowID) {
        workspace?.toolWindowManager.toggle(id)
    }

    func hideAllToolWindows() {
        workspace?.toolWindowManager.hideAll()
    }

    func toggleBottomToolWindowMaximized() {
        guard let manager = workspace?.toolWindowManager else { return }

        if manager.active(.bottom) == nil {
            manager.show(.terminal)
        }
        manager.bottomMaximized.toggle()
    }

    // PanelDescriptor, used for an array of panels, for use with "Hide interface".
    private struct PanelDescriptor {
        /// Returns the current `isCollapsed` value for the panel.
        let isCollapsed: () -> Bool
        /// Returns the last stored previous state (or `nil` if none).
        let getPrevCollapsed: () -> Bool?
        /// Stores a new previous state (`nil` to clear).
        let setPrevCollapsed: (Bool?) -> Void
        /// Performs the actual toggle action for the panel.
        let toggle: () -> Void
    }

    // The panels which "Hide interface" should interact with.
    private var panels: [PanelDescriptor] {
        [
            PanelDescriptor(
                isCollapsed: { self.workspace?.toolWindowManager.active(.left) == nil },
                getPrevCollapsed: { self.prevLeftToolWindowHidden },
                setPrevCollapsed: { self.prevLeftToolWindowHidden = $0 },
                toggle: { self.toggleLeftPanel() }
            ),
            PanelDescriptor(
                isCollapsed: { self.workspace?.toolWindowManager.active(.bottom) == nil },
                getPrevCollapsed: { self.prevBottomToolWindowHidden },
                setPrevCollapsed: { self.prevBottomToolWindowHidden = $0 },
                toggle: { self.toggleLastPanel() }
            ),
            PanelDescriptor(
                isCollapsed: { self.toolbarCollapsed },
                getPrevCollapsed: { self.prevToolbarCollapsed },
                setPrevCollapsed: { self.prevToolbarCollapsed = $0 },
                toggle: { self.toggleToolbar() }
            )
        ]
    }

    /// Returns `true` if at least one panel that was visible is still collapsed, meaning the interface is still hidden
    func isInterfaceStillHidden() -> Bool {
        // Some panels do not yet have a remembered state
        if panels.contains(where: { $0.getPrevCollapsed() == nil }) {
            // Hidden only if all panels are collapsed
            return panels.allSatisfy { $0.isCollapsed() }
        }

        // All panels have a remembered state. Check if any that were visible are still collapsed
        let stillHidden = panels.contains { descriptor in
            guard let prev = descriptor.getPrevCollapsed() else { return false }
            return !prev && descriptor.isCollapsed()
        }

        // If the interface has been restored, reset the remembered states
        if !stillHidden {
            Task { [weak self] in
                self?.resetStoredInterfaceCollapseState()
            }
        }

        return stillHidden
    }

    /// Function for toggling the interface elements on or off
    ///
    /// - Parameter shouldHide: Pass `true` to hide all interface panels (and remember their current states),
    /// or `false` to restore them to how they were before hiding.
    func toggleInterface(shouldHide: Bool) {
        // Store the current layout before hiding
        if shouldHide {
            storeInterfaceCollapseState()
        }

        // Iterate over all panels and update their state as needed
        for panel in panels {
            let targetState = determineDesiredCollapseState(
                shouldHide: shouldHide,
                currentlyCollapsed: panel.isCollapsed(),
                previouslyCollapsed: panel.getPrevCollapsed()
            )
            if panel.isCollapsed() != targetState {
                panel.toggle()
            }
        }
    }

    /// Calculates the collapse state an interface element should have after a hide / show toggle.
    /// - Parameters:
    ///   - shouldHide: `true` when we’re hiding the whole interface.
    ///   - currentlyCollapsed: The panels current state
    ///   - previouslyCollapsed: The state we saved the last time we hid the UI, if any.
    /// - Returns: `true` for visible element, `false` for collapsed element
    func determineDesiredCollapseState(shouldHide: Bool, currentlyCollapsed: Bool, previouslyCollapsed: Bool?) -> Bool {
        // If ShouldHide, everything should close
        if shouldHide {
            return true
        }

        // If not hiding, and not currently collapsed, the panel should remain as such.
        if !currentlyCollapsed {
            return false
        }

        // If the panel is currently collapsed and we are "showing" or "restoring":
        // Option 1: Restore to its previously remembered state if available.
        // Option 2: If no previously remembered state, default to making it visible (not collapsed).
        return previouslyCollapsed ?? false
    }

    /// Function for storing the current interface visibility states
    func storeInterfaceCollapseState() {
        for panel in panels {
            panel.setPrevCollapsed(panel.isCollapsed())
        }
    }

    /// Function for resetting the stored interface visibility states
    func resetStoredInterfaceCollapseState() {
        for panel in panels {
            panel.setPrevCollapsed(nil)
        }
    }
}
