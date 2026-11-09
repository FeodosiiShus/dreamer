import Foundation

extension ToolWindowManager {
    func hideCallback(for id: ToolWindowID) -> () -> Void {
        { self.hide(id) }
    }
}
