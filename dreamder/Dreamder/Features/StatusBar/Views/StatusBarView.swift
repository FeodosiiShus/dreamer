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
            HStack(spacing: StatusBarWidgetMetrics.widgetSpacing) {
                StatusBarProgressIndicator(handler: workspace.taskNotificationHandler)
                StatusBarCursorPositionLabel()
                StatusBarLineEndSelector(document: tab?.file.fileDocument)
                StatusBarEncodingSelector(document: tab?.file.fileDocument)
                StatusBarIndentSelector(document: tab?.file.fileDocument)
                StatusBarNotificationsButton()
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, StatusBarWidgetMetrics.barPadding)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Islands.glassIslandTint)
        .glassEffect(.regular, in: Rectangle())
        .environment(\.colorScheme, .dark)
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
            command: Self.togglePanelCommand(for: utilityAreaViewModel)
        )
    }

    static func togglePanelCommand(for utilityAreaViewModel: UtilityAreaViewModel) -> () -> Void {
        { [weak utilityAreaViewModel] in utilityAreaViewModel?.togglePanel() }
    }
}

struct StatusBarProjectBreadcrumbs: View {
    @Environment(WorkspaceDocument.self) private var workspace

    let file: CEWorkspaceFile?
    let projectURL: URL?

    var projectName: String {
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
        HStack(spacing: 0) {
            StatusBarWidgetText(text: projectName)
                .truncationMode(.middle)
                .statusBarWidgetFrame()
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
        StatusBarWidgetButton(
            action: Self.revealing(relativePath: relativePath, projectURL: projectURL, workspace: workspace)
        ) { hovering in
            StatusBarWidgetText(text: name, isHovering: hovering)
                .truncationMode(.middle)
        }
        .help("Reveal in Project")
    }

    static func revealing(relativePath: String, projectURL: URL?, workspace: WorkspaceDocument) -> () -> Void {
        { reveal(relativePath: relativePath, projectURL: projectURL, workspace: workspace) }
    }

    static func reveal(relativePath: String, projectURL: URL?, workspace: WorkspaceDocument) {
        workspace.toolWindowManager.show(.project)
        guard let projectURL,
              let item = workspace.workspaceFileManager?.getFile(
                  projectURL.appendingPathComponent(relativePath).path,
                  createIfNotFound: true
              ) else { return }
        NSApp.sendAction(#selector(ProjectNavigatorViewController.revealItem(_:)), to: nil, from: item.id)
    }

    static func revealingFile(workspace: WorkspaceDocument) -> () -> Void {
        { revealFile(workspace: workspace) }
    }

    static func revealFile(workspace: WorkspaceDocument) {
        workspace.toolWindowManager.show(.project)
        NSApp.sendAction(#selector(ProjectNavigatorViewController.revealFile(_:)), to: nil, from: nil)
    }

    private func fileCrumb(_ file: CEWorkspaceFile) -> some View {
        StatusBarWidgetButton(action: Self.revealingFile(workspace: workspace)) { hovering in
            HStack(spacing: 4) {
                Image(IntelliJIcon.fileIcon(for: file.name))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: StatusBarWidgetMetrics.iconSize, height: StatusBarWidgetMetrics.iconSize)
                StatusBarWidgetText(text: file.name, isHovering: hovering)
                    .truncationMode(.middle)
            }
        }
        .help("Reveal in Project")
    }
}

extension NSCursor {
    func setHovering(_ isHovering: Bool) {
        if isHovering {
            push()
        } else {
            pop()
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover(perform: cursor.setHovering)
    }
}
