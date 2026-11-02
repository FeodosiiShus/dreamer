import Combine
import SwiftUI

final class ProjectNavigatorOpenFilesModel: ObservableObject {
    @Published private(set) var files: [CEWorkspaceFile] = []
    @Published private(set) var selectedFileID: String?

    private weak var editorManager: EditorManager?
    private var cancellables = Set<AnyCancellable>()

    func attach(_ editorManager: EditorManager) {
        guard self.editorManager !== editorManager else {
            rebuild()
            return
        }
        self.editorManager = editorManager
        cancellables.removeAll()

        let tabChanges = editorManager.$activeEditor
            .flatMap { editor in editor.$tabs.map { _ in () }.eraseToAnyPublisher() }
            .eraseToAnyPublisher()
        let selectionChanges = editorManager.$activeEditor
            .flatMap { editor in editor.$selectedTab.map { _ in () }.eraseToAnyPublisher() }
            .eraseToAnyPublisher()
        let activeChanges = editorManager.$activeEditor
            .map { _ in () }
            .eraseToAnyPublisher()
        let layoutChanges = editorManager.$editorLayout
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.Merge4(tabChanges, activeChanges, layoutChanges, selectionChanges)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        rebuild()
    }

    private func rebuild() {
        guard let editorManager else { return }
        var result: [CEWorkspaceFile] = []
        var seen = Set<String>()
        for editor in editors(of: editorManager) {
            for tab in editor.tabs where seen.insert(tab.file.id).inserted {
                result.append(tab.file)
            }
        }
        if result != files {
            files = result
        }
        let selection = editorManager.activeEditor.selectedTab?.file.id
        if selectedFileID != selection {
            selectedFileID = selection
        }
    }

    private func editors(of editorManager: EditorManager) -> [Editor] {
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
    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var editorManager: EditorManager

    @StateObject private var model = ProjectNavigatorOpenFilesModel()

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

    private func row(for file: CEWorkspaceFile) -> some View {
        let isSelected = model.selectedFileID == file.id
        let directory = directoryName(of: file)
        return Button {
            editorManager.openTab(item: file)
        } label: {
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
