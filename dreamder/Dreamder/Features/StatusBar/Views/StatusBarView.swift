//
//  StatusBarView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 19.03.22.
//

import AppKit
import SwiftUI

/// # StatusBarView
///
/// A View that lives on the bottom of the window and offers information
/// about compilation errors/warnings, git,  cursor position in text,
/// indentation width (in spaces), text encoding and linebreak.
///
/// Also information about the file size and dimensions, if available.
///
/// Additionally it offers a togglable/resizable drawer which can
/// host a terminal or additional debug information
///
struct StatusBarView: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel

    private var tab: EditorInstance? {
        editorManager.activeEditor.selectedTab
    }

    static var height: CGFloat {
        Islands.statusBarHeight
    }

    init() {}

    /// The actual status bar
    var body: some View {
        HStack(spacing: 8) {
            StatusBarProjectBreadcrumbs(
                file: tab?.file,
                projectURL: workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL
            )
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                StatusBarCursorPositionLabel()
                StatusBarLineEndSelector(document: tab?.file.fileDocument)
                StatusBarEncodingSelector(document: tab?.file.fileDocument)
                StatusBarIndentSelector()
                StatusBarNotificationsButton()
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .onAppear {
            registerUtilityAreaCommand()
            SearchEverywhereRecentFilesStore.shared.startTracking(for: workspace)
        }
        .accessibilityElement(children: .contain)
    }

    private func registerUtilityAreaCommand() {
        CommandManager.shared.addCommand(
            name: "Toggle Utility Area",
            title: "Toggle Utility Area",
            id: "open.drawer",
            command: { [weak utilityAreaViewModel] in utilityAreaViewModel?.togglePanel() }
        )
    }
}

private struct StatusBarProjectBreadcrumbs: View {
    @Environment(WorkspaceDocument.self) private var workspace

    let file: CEWorkspaceFile?
    let projectURL: URL?

    private var projectName: String {
        projectURL?.lastPathComponent ?? "Empty"
    }

    private var folderNames: [String] {
        guard let file, let projectURL else { return [] }
        let fileComponents = file.url.standardizedFileURL.pathComponents
        let rootComponents = projectURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              fileComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
            return []
        }
        return Array(fileComponents.dropFirst(rootComponents.count).dropLast())
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(projectName)
                .foregroundColor(Islands.secondaryForeground)
                .lineLimit(1)
                .truncationMode(.middle)
            ForEach(folderNames.indices, id: \.self) { index in
                separator
                folderCrumb(
                    folderNames[index],
                    relativePath: folderNames[0...index].joined(separator: "/")
                )
            }
            if let file {
                separator
                fileCrumb(file)
            }
        }
        .font(Islands.smallFont)
        .frame(minWidth: 0, alignment: .leading)
        .clipped()
    }

    private var separator: some View {
        Image("general/chevronRight")
            .resizable()
            .interpolation(.high)
            .frame(width: 10, height: 10)
            .opacity(0.6)
            .fixedSize()
    }

    private func folderCrumb(_ name: String, relativePath: String) -> some View {
        Button {
            reveal(relativePath: relativePath)
        } label: {
            Text(name)
                .foregroundColor(Islands.secondaryForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reveal in Project")
    }

    private func reveal(relativePath: String) {
        workspace.toolWindowManager.show(.project)
        guard let projectURL,
              let item = workspace.workspaceFileManager?.getFile(
                  projectURL.appendingPathComponent(relativePath).path,
                  createIfNotFound: true
              ) else { return }
        NSApp.sendAction(#selector(ProjectNavigatorViewController.revealItem(_:)), to: nil, from: item.id)
    }

    private func fileCrumb(_ file: CEWorkspaceFile) -> some View {
        Button {
            workspace.toolWindowManager.show(.project)
            NSApp.sendAction(#selector(ProjectNavigatorViewController.revealFile(_:)), to: nil, from: nil)
        } label: {
            HStack(spacing: 4) {
                Image(IntelliJIcon.fileIcon(for: file.name))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                Text(file.name)
                    .foregroundColor(Islands.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reveal in Project")
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover {
            if $0 {
                cursor.push()
            } else {
                cursor.pop()
            }
        }
    }
}
