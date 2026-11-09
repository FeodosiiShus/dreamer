import AppKit
import SwiftUI

nonisolated struct BranchesCompareCommit: Identifiable, Hashable {
    let hash: String
    let subject: String
    let author: String
    let date: String

    var id: String { hash }

    static func list(from output: String) -> [BranchesCompareCommit] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: "|")
                guard parts.count >= 4, !parts[0].isEmpty else { return nil }
                return BranchesCompareCommit(
                    hash: parts[0],
                    subject: parts[1..<(parts.count - 2)].joined(separator: "|"),
                    author: parts[parts.count - 2],
                    date: parts[parts.count - 1]
                )
            }
    }
}

@Observable
@MainActor
final class BranchesCompareViewModel {
    let branch: String
    let current: String
    private let manager: SourceControlManager

    var branchOnly: [BranchesCompareCommit] = []
    var currentOnly: [BranchesCompareCommit] = []
    var isLoading = true
    var errorMessage: String?

    init(manager: SourceControlManager, branch: String, current: String) {
        self.manager = manager
        self.branch = branch
        self.current = current
    }

    var title: String {
        "Comparing \(branch) with \(current)"
    }

    func load() async {
        isLoading = true
        do {
            let branchOnly = try await manager.branchOpsCommits(branch: branch, notIn: current)
            let currentOnly = try await manager.branchOpsCommits(branch: current, notIn: branch)
            self.branchOnly = branchOnly
            self.currentOnly = currentOnly
            errorMessage = nil
        } catch {
            errorMessage = (error as? GitClient.GitClientError)?.description ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct BranchesCompareView: View {
    let model: BranchesCompareViewModel

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(Islands.smallFont)
                                .foregroundStyle(Islands.secondaryForeground)
                        }
                        section(
                            title: "Commits in \(model.branch) not in \(model.current)",
                            commits: model.branchOnly
                        )
                        section(
                            title: "Commits in \(model.current) not in \(model.branch)",
                            commits: model.currentOnly
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Islands.island)
        .task { await model.load() }
    }

    private func section(title: String, commits: [BranchesCompareCommit]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
            if commits.isEmpty {
                Text("No commits")
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
            } else {
                ForEach(commits) { commit in
                    HStack(spacing: 8) {
                        Text(commit.hash)
                            .font(.system(size: Islands.smallFontSize, design: .monospaced))
                            .foregroundStyle(Islands.secondaryForeground)
                        Text(commit.subject)
                            .font(Islands.uiFont)
                            .foregroundStyle(Islands.foreground)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(commit.author)
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.secondaryForeground)
                        Text(commit.date)
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.secondaryForeground)
                    }
                    .frame(height: Islands.listRowHeight)
                }
            }
        }
    }
}

@MainActor
final class BranchesCompareWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let compareWindow: NSWindow

    init(model: BranchesCompareViewModel) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 560)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: BranchesCompareView(model: model))
        compareWindow = window
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func place(relativeTo parent: NSWindow?) {
        let size = compareWindow.frame.size
        var origin = NSPoint.zero
        if let parent {
            origin = NSPoint(
                x: parent.frame.midX - size.width / 2,
                y: parent.frame.midY - size.height / 2
            )
        } else if let screen = NSScreen.main {
            origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }
        compareWindow.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
enum BranchesComparePresenter {
    private static var windows: [String: BranchesCompareWindowController] = [:]

    static func show(workspace: WorkspaceDocument, branch: String, current: String) {
        guard let manager = workspace.sourceControlManager else { return }
        let key = "\(manager.repositoryURL.path(percentEncoded: false))|\(current)|\(branch)"
        if let controller = windows[key], let window = controller.window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = BranchesCompareViewModel(manager: manager, branch: branch, current: current)
        let controller = BranchesCompareWindowController(model: model)
        controller.onClose = { windows[key] = nil }
        windows[key] = controller
        controller.place(relativeTo: workspace.windowControllers.first?.window)
        controller.showWindow(nil)
        NSApp.activate()
    }
}
