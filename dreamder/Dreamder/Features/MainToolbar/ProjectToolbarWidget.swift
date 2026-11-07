import SwiftUI

struct ProjectToolbarWidget: View {
    let workspace: WorkspaceDocument

    @State private var isHovering = false
    @State private var menuAnchor = MainToolbarMenuAnchor()

    private var projectName: String {
        workspace.workspaceFileManager?.folderUrl.lastPathComponent
            ?? workspace.displayName
            ?? "Empty"
    }

    var body: some View {
        HStack(spacing: 6) {
            ProjectBadge(name: projectName)
            Text(projectName)
                .font(Islands.uiFont)
                .foregroundColor(Islands.foreground)
                .lineLimit(1)
            Image("general/chevronDown")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Islands.toolbarControlHeight)
        .mainToolbarGlass(isHovering: isHovering)
        .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
        .contentShape(Capsule())
        .onTapGesture {
            menuAnchor.present(
                MainToolbarMenuActions.shared.projectMenu(window: menuAnchor.view?.window)
            )
        }
        .onHover { isHovering = $0 }
        .help("Project")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project")
        .accessibilityValue(projectName)
        .accessibilityAddTraits(.isButton)
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
            .frame(width: 20, height: 20)
            .overlay {
                Text(initials)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
    }
}
