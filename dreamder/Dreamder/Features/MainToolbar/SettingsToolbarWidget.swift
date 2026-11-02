import SwiftUI

struct SettingsToolbarWidget: View {
    @State private var isHovering = false
    @State private var menuAnchor = MainToolbarMenuAnchor()

    var body: some View {
        MainToolbarIconContent(icon: "general/settings", isHovering: isHovering)
            .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
            .onTapGesture {
                menuAnchor.present(MainToolbarMenuActions.shared.settingsMenu())
            }
            .onHover { isHovering = $0 }
            .help("Settings")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
    }
}
