import SwiftUI

struct SettingsToolbarWidget: View {
    @State private var hover: MainToolbarHoverState
    @State private var menuAnchor: MainToolbarMenuAnchor

    init(menuAnchor: MainToolbarMenuAnchor = MainToolbarMenuAnchor(), hover: MainToolbarHoverState = MainToolbarHoverState()) {
        _menuAnchor = State(initialValue: menuAnchor)
        _hover = State(initialValue: hover)
    }

    func showMenu() {
        Self.presentMenu(on: menuAnchor)
    }

    static func presentMenu(on anchor: MainToolbarMenuAnchor) {
        anchor.present(MainToolbarMenuActions.shared.settingsMenu())
    }

    var body: some View {
        Button(action: showMenu) {
            MainToolbarIconContent(icon: "general/settings_20")
        }
        .buttonStyle(.actionButton(look: .mainToolbarButton, isHovering: hover.isHovering))
        .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
        .onHover(perform: hover.setHovering)
        .help("Settings")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(.isButton)
        .fixedSize()
    }
}
