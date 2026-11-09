import SwiftUI

struct StructureCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            StructureMenuItems(windowController: windowController)
        }
    }
}

struct StructureMenuItems: View {
    let windowController: DreamderWindowController?
    let sendAction: @MainActor (Selector) -> Void

    init(
        windowController: DreamderWindowController?,
        sendAction: @escaping @MainActor (Selector) -> Void = MenuResponderChain.send
    ) {
        self.windowController = windowController
        self.sendAction = sendAction
    }

    var body: some View {
        Button("File Structure", action: showFileStructure)
            .keymapShortcut(.fileStructure)
            .disabled(windowController == nil)
    }

    func showFileStructure() {
        sendAction(#selector(DreamderWindowController.showFileStructure(_:)))
    }
}
