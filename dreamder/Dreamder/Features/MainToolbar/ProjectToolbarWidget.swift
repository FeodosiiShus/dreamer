import SwiftUI

struct ProjectToolbarWidget: View {
    let workspace: WorkspaceDocument

    @State private var hover: MainToolbarHoverState
    @State private var menuAnchor: MainToolbarMenuAnchor

    init(
        workspace: WorkspaceDocument,
        menuAnchor: MainToolbarMenuAnchor = MainToolbarMenuAnchor(),
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.workspace = workspace
        _menuAnchor = State(initialValue: menuAnchor)
        _hover = State(initialValue: hover)
    }

    func showMenu() {
        Self.presentMenu(on: menuAnchor)
    }

    static func presentMenu(on anchor: MainToolbarMenuAnchor) {
        anchor.present(MainToolbarMenuActions.shared.projectMenu(window: anchor.view?.window))
    }

    private var projectName: String {
        workspace.workspaceFileManager?.folderUrl.lastPathComponent ?? workspace.displayName
    }

    var body: some View {
        Button(action: showMenu) {
            MainToolbarDropdownLabel(text: projectName) {
                ProjectBadge(name: projectName)
            }
        }
        .buttonStyle(.actionButton(look: .mainToolbarDropdown, isHovering: hover.isHovering))
        .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
        .onHover(perform: hover.setHovering)
        .help("Project")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Project")
        .accessibilityValue(projectName)
        .accessibilityAddTraits(.isButton)
        .fixedSize()
    }
}

private struct ProjectBadge: View {
    let name: String

    private static let colors: [Color] = [
        Color(hex: 0xC85A54),
        Color(hex: 0x4F7FC4),
        Color(hex: 0x4E8F5A),
        Color(hex: 0xB08A3E),
        Color(hex: 0x8A5BA8),
        Color(hex: 0x3E8C99),
        Color(hex: 0xB2713F),
        Color(hex: 0x6E7480)
    ]

    private var initials: String {
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." || $0 == " " })
        guard let first = parts.first else { return "?" }
        if parts.count == 1 {
            return String(first.prefix(2)).uppercased()
        }
        return String([first.first, parts[1].first].compactMap { $0 }).uppercased()
    }

    private var color: Color {
        var hash = 5381
        for scalar in name.lowercased().unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return Self.colors[Int(hash.magnitude % UInt(Self.colors.count))]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: MainToolbarMetrics.projectAvatarSize, height: MainToolbarMetrics.projectAvatarSize)
            .overlay {
                Text(initials)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
    }
}
