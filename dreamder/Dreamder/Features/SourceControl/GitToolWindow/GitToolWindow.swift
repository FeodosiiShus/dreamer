import AppKit
import SwiftUI

struct GitToolWindow: View {
    static let branchesWidthRange: ClosedRange<CGFloat> = 150...420
    static let detailsWidthRange: ClosedRange<CGFloat> = 220...620

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var model: GitToolWindowModel

    init(model: GitToolWindowModel = GitToolWindowModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(
                title: "Git",
                tabs: {
                    ToolWindowTab(title: model.logModel.tabTitle, isSelected: model.pane == .log, action: model.showLog)
                    GitConsoleTab(
                        log: GitConsoleLog.log(for: sourceControlManager.repositoryURL),
                        isSelected: model.consoleSelection
                    )
                    ToolWindowTab(title: "Shelf", isSelected: model.pane == .shelf, action: model.showShelf)
                },
                actions: {
                    GitToolWindowActions(
                        model: model,
                        manager: sourceControlManager,
                        toolWindows: workspace.toolWindowManager
                    )
                }
            )

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            if model.showsConsole {
                GitConsoleView(log: GitConsoleLog.log(for: sourceControlManager.repositoryURL))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sourceControlManager.isGitRepository {
                if model.pane == .shelf {
                    ShelfView(model: model.shelfModel)
                } else {
                    content
                }
            } else {
                Text("Not a git repository")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task {
            await model.refresh(manager: sourceControlManager)
        }
        .onChange(of: sourceControlManager.isGitRepository) { _, isRepository in
            guard isRepository else { return }
            Task {
                await model.refresh(manager: sourceControlManager)
            }
        }
        .onChange(of: sourceControlManager.currentBranch) { _, _ in
            guard sourceControlManager.isGitRepository else { return }
            Task {
                await model.logModel.load(manager: sourceControlManager)
            }
        }
    }

    private var content: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            GitLogBranchesPane(viewModel: model.logModel)
                .frame(width: model.branchesWidth)

            GitPaneDivider(width: $model.branchesWidth, range: Self.branchesWidthRange)

            VStack(spacing: 0) {
                GitLogFilterBar(viewModel: model.logModel)
                GitLogCommitTable(viewModel: model.logModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GitPaneDivider(width: $model.detailsWidth, range: Self.detailsWidthRange, inverted: true)

            GitLogDetailsPane(viewModel: model.logModel)
                .frame(width: model.detailsWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

nonisolated struct GitPaneDividerDrag: Equatable, Sendable {
    let range: ClosedRange<CGFloat>
    let inverted: Bool
    private(set) var startWidth: CGFloat?

    init(range: ClosedRange<CGFloat>, inverted: Bool = false) {
        self.range = range
        self.inverted = inverted
    }

    mutating func resolvedWidth(_ current: CGFloat, translation: CGFloat) -> CGFloat {
        let base = startWidth ?? current
        startWidth = base
        let delta = inverted ? -translation : translation
        return min(max(base + delta, range.lowerBound), range.upperBound)
    }

    mutating func end() {
        startWidth = nil
    }
}

struct GitPaneDivider: View {
    @Binding var width: CGFloat
    @State private var drag: GitPaneDividerDrag

    init(width: Binding<CGFloat>, range: ClosedRange<CGFloat>, inverted: Bool = false) {
        _width = width
        _drag = State(initialValue: GitPaneDividerDrag(range: range, inverted: inverted))
    }

    static func cursor(isHovering: Bool) -> NSCursor {
        isHovering ? .resizeLeftRight : .arrow
    }

    var body: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(width: 1)
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover(perform: hover)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged(reading(\.translation, into: dragChanged))
                    .onEnded(discarding(dragEnded))
            )
    }

    func hover(_ isHovering: Bool) {
        Self.cursor(isHovering: isHovering).set()
    }

    func dragChanged(_ translation: CGSize) {
        width = drag.resolvedWidth(width, translation: translation.width)
    }

    func dragEnded() {
        drag.end()
    }
}

struct GitToolWindowActions: View {
    let model: GitToolWindowModel
    let manager: SourceControlManager
    let toolWindows: ToolWindowManager

    var body: some View {
        ToolWindowActionButton(icon: "general/refresh", help: "Refresh", action: startRefresh)
        ToolWindowActionButton(icon: "general/hide", help: "Hide", action: hide)
    }

    func startRefresh() {
        Task { await model.refresh(manager: manager) }
    }

    func hide() {
        toolWindows.hide(.git)
    }
}
