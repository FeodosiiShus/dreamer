import CoreGraphics

enum EditorTabOverflow {
    static func hiddenTabs(
        openedTabs: [CEWorkspaceFile.ID],
        frames: [CEWorkspaceFile.ID: CGRect],
        viewport: CGRect
    ) -> [CEWorkspaceFile.ID] {
        guard viewport.width > 1 else { return [] }
        return openedTabs.filter { id in
            guard let frame = frames[id] else { return false }
            return frame.minX < viewport.minX - 0.5 || frame.maxX > viewport.maxX + 0.5
        }
    }
}
