import SwiftUI

@Observable
final class ProjectNavigatorOpenFilesModel {
    private struct Snapshot: Equatable {
        let files: [CEWorkspaceFile]
        let selectedFileID: String?
    }

    private(set) var files: [CEWorkspaceFile] = []
    private(set) var selectedFileID: String?

    @ObservationIgnored private weak var editorManager: EditorManager?
    @ObservationIgnored private var observation: Task<Void, Never>?

    func attach(_ editorManager: EditorManager) {
        guard self.editorManager !== editorManager else {
            rebuild()
            return
        }
        self.editorManager = editorManager
        observation?.cancel()
        observation = Task { [weak self] in
            for await snapshot in Observations({ Self.snapshot(of: editorManager) }) {
                self?.apply(snapshot)
            }
        }

        rebuild()
    }

    isolated deinit {
        observation?.cancel()
    }

    private func rebuild() {
        guard let editorManager else { return }
        apply(Self.snapshot(of: editorManager))
    }

    private func apply(_ snapshot: Snapshot) {
        if snapshot.files != files {
            files = snapshot.files
        }
        if selectedFileID != snapshot.selectedFileID {
            selectedFileID = snapshot.selectedFileID
        }
    }

    private static func snapshot(of editorManager: EditorManager) -> Snapshot {
        var result: [CEWorkspaceFile] = []
        var seen = Set<String>()
        for editor in editors(of: editorManager) {
            for tab in editor.tabs where seen.insert(tab.file.id).inserted {
                result.append(tab.file)
            }
        }
        return Snapshot(files: result, selectedFileID: editorManager.activeEditor.selectedTab?.file.id)
    }

    private static func editors(of editorManager: EditorManager) -> [Editor] {
        var result: [Editor] = [editorManager.activeEditor]
        func collect(_ layout: EditorLayout) {
            switch layout {
            case .one(let editor):
                if !result.contains(where: { $0 === editor }) {
                    result.append(editor)
                }
            case .vertical(let data), .horizontal(let data):
                data.editorLayouts.forEach(collect)
            }
        }
        collect(editorManager.editorLayout)
        return result
    }
}

struct ProjectNavigatorOpenFilesView: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager

    @State private var model = ProjectNavigatorOpenFilesModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if model.files.isEmpty {
                    Text("No open files")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.secondaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(model.files, id: \.id) { file in
                        row(for: file)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.attach(editorManager)
        }
        .onChange(of: editorManager.activeEditor.id) { _, _ in
            model.attach(editorManager)
        }
    }

    static func openAction(for file: CEWorkspaceFile, in editorManager: EditorManager) -> () -> Void {
        { editorManager.openTab(item: file) }
    }

    private func row(for file: CEWorkspaceFile) -> some View {
        let isSelected = model.selectedFileID == file.id
        let directory = directoryName(of: file)
        return Button(action: Self.openAction(for: file, in: editorManager)) {
            HStack(spacing: 6) {
                Image(IntelliJIcon.fileIcon(for: file.name))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                Text(file.name)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if !directory.isEmpty {
                    Text(directory)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .frame(height: Islands.treeRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius)
                    .fill(isSelected ? Islands.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func directoryName(of file: CEWorkspaceFile) -> String {
        guard let root = workspace.workspaceFileManager?.folderUrl else { return "" }
        let rootPath = root.standardizedFileURL.path
        let directoryPath = file.url.standardizedFileURL.deletingLastPathComponent().path
        guard directoryPath.hasPrefix(rootPath) else { return "" }
        return String(directoryPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
