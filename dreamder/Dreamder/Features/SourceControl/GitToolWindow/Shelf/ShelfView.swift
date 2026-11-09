import SwiftUI

struct ShelfView: View {
    static let toolbarHeight: CGFloat = 30
    static let toolbarInset: CGFloat = 6
    static let buttonSize: CGFloat = 26
    static let buttonSpacing: CGFloat = 2
    static let listWidth: CGFloat = 300

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    let model: ShelfModel
    let showConflicts: (WorkspaceDocument) -> Void

    init(
        model: ShelfModel,
        showConflicts: @escaping (WorkspaceDocument) -> Void = { MergeToolPresenter.showConflicts(workspace: $0) }
    ) {
        self.model = model
        self.showConflicts = showConflicts
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            if model.shelves.isEmpty {
                Text("No shelved changes")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    shelfList
                        .frame(width: Self.listWidth)

                    Rectangle()
                        .fill(Islands.separator)
                        .frame(width: 1)

                    if let shelf = model.selectedShelf {
                        filesPane(shelf)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let currentWorkspace = workspace
            let presentConflicts = showConflicts
            model.attach(manager: sourceControlManager, showConflicts: { presentConflicts(currentWorkspace) })
            await model.reload()
        }
        .onChange(of: sourceControlManager.stashEntries) { _, _ in
            model.enqueue { await $0.reload() }
        }
    }

    private var toolbar: some View {
        let hasSelection = model.selectedShelf != nil
        return HStack(spacing: Self.buttonSpacing) {
            ToolWindowActionButton(icon: "vcs/shelve", help: "Shelve Changes…", action: { model.enqueue { await $0.shelveAllChanges() } })
            ToolWindowActionButton(icon: "vcs/unshelve", help: "Unshelve", action: { model.enqueue { await $0.unshelveSelected(keep: false) } })
                .disabled(!hasSelection)
            ToolWindowActionButton(icon: "general/copy", help: "Unshelve and Keep", action: { model.enqueue { await $0.unshelveSelected(keep: true) } })
                .disabled(!hasSelection)
            ToolWindowActionButton(icon: "general/edit", help: "Rename…", action: { model.enqueue { await $0.renameSelected() } })
                .disabled(!hasSelection)
            ToolWindowActionButton(icon: "general/delete", help: "Delete", action: { model.enqueue { await $0.deleteSelected() } })
                .disabled(!hasSelection)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.toolbarInset)
        .frame(height: Self.toolbarHeight)
    }

    private var shelfList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.shelves) { shelf in
                    ShelfRow(shelf: shelf, model: model)
                }
            }
        }
    }

    private func filesPane(_ shelf: GitShelf) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(shelf.files.count == 1 ? "1 file" : "\(shelf.files.count) files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shelf.files, id: \.self) { file in
                        ShelfFileRow(file: file)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ShelfRow: View {
    let shelf: GitShelf
    let model: ShelfModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image("vcs/shelve")
                .resizable()
                .frame(width: 16, height: 16)
            Text(shelf.name)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Text(shelf.files.count == 1 ? "1 file" : "\(shelf.files.count) files")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(GitLogRelativeDate.string(for: shelf.date))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.listRowHeight)
        .background(Self.background(isSelected: model.selectedHash == shelf.hash, isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.select(shelf) }
        .contextMenu { ShelfRowMenu(shelf: shelf, model: model) }
    }

    static func background(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected {
            return Islands.selection
        }
        return isHovering ? Islands.hover : Color.clear
    }
}

struct ShelfRowMenu: View {
    let shelf: GitShelf
    let model: ShelfModel

    var body: some View {
        Button("Unshelve") { model.enqueue { await $0.unshelve(shelf, keep: false) } }
        Button("Unshelve and Keep") { model.enqueue { await $0.unshelve(shelf, keep: true) } }
        Divider()
        Button("Rename…") { model.enqueue { await $0.rename(shelf) } }
        Button("Delete") { model.enqueue { await $0.delete(shelf) } }
    }
}

struct ShelfFileRow: View {
    let file: GitShelfFile

    private var name: String {
        (file.path as NSString).lastPathComponent
    }

    private var directory: String {
        (file.path as NSString).deletingLastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(IntelliJIcon.fileIcon(for: name))
                .resizable()
                .frame(width: 16, height: 16)
            Text(name)
                .font(Islands.uiFont)
                .foregroundStyle(file.status.fileStatusColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Text(directory)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.listRowHeight)
        .help(file.path)
    }
}
