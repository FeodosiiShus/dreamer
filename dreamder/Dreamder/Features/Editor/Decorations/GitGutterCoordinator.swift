import AppKit
import Observation
import CodeEditSourceEditor
import CodeEditTextView

final class GitGutterCoordinator: TextViewCoordinator {
    private let fileURL: URL?
    private weak var controller: TextViewController?
    private weak var workspace: WorkspaceDocument?
    private weak var markerView: GitGutterMarkerView?
    private var gutterFrameObserver: NSObjectProtocol?

    private var repositoryObservation: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var headTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration
    private var changes: [GitLineChange] = []
    private var headText: String?
    private var isTrackingRepository = false
    private var isUntrackedFile = false

    private nonisolated struct Snapshot: Sendable {
        let changes: [GitLineChange]
        let untracked: Bool
    }

    private nonisolated struct RepositorySignature: Equatable, Sendable {
        var isGitRepository = false
        var branchName: String?
        var ahead = 0
        var behind = 0
        var changedFiles: Set<GitChangedFile> = []
        var unsyncedAhead = 0
        var unsyncedBehind = 0

        @MainActor
        init(manager: SourceControlManager) {
            isGitRepository = manager.isGitRepository
            branchName = manager.currentBranch?.longName
            ahead = manager.currentBranch?.ahead ?? 0
            behind = manager.currentBranch?.behind ?? 0
            changedFiles = Set(manager.changedFiles)
            unsyncedAhead = manager.numberOfUnsyncedCommits.ahead
            unsyncedBehind = manager.numberOfUnsyncedCommits.behind
        }
    }

    init(codeFile: CodeFileDocument, debounceInterval: Duration = .milliseconds(500)) {
        fileURL = codeFile.fileURL
        self.debounceInterval = debounceInterval
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        installMarkerViewIfNeeded(controller: controller)
        guard workspace == nil, let fileURL, let workspace = fileURL.findWorkspace() else {
            return
        }
        self.workspace = workspace
        guard let manager = workspace.sourceControlManager else { return }
        repositoryObservation = Task { [weak self, manager] in
            let signatures = Observations { RepositorySignature(manager: manager) }
            var previous: RepositorySignature?
            for await signature in signatures {
                guard let self else { return }
                guard signature != previous else { continue }
                previous = signature
                if signature.isGitRepository {
                    refreshFromGit()
                } else {
                    stopTracking()
                }
            }
        }
    }

    var currentChanges: [GitLineChange] { changes }

    var loadedHeadText: String? { headText }

    func textViewDidChangeText(controller: TextViewController) {
        installMarkerViewIfNeeded(controller: controller)
        scheduleMemoryRefresh()
    }

    func destroy() {
        refreshTask?.cancel()
        refreshTask = nil
        headTask?.cancel()
        headTask = nil
        memoryTask?.cancel()
        memoryTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        repositoryObservation?.cancel()
        repositoryObservation = nil
        if let gutterFrameObserver {
            NotificationCenter.default.removeObserver(gutterFrameObserver)
        }
        gutterFrameObserver = nil
        markerView?.removeFromSuperview()
        markerView = nil
        controller = nil
        workspace = nil
        headText = nil
        isTrackingRepository = false
        isUntrackedFile = false
        changes = []
    }

    private func installMarkerViewIfNeeded(controller: TextViewController) {
        guard markerView == nil,
              let gutter = Self.gutterView(in: controller.scrollView),
              let textView = controller.textView else {
            return
        }
        let view = GitGutterMarkerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.textView = textView
        view.frame = Self.markerFrame(in: gutter)
        view.previousContent = { [weak self] change in self?.previousContent(for: change) }
        view.rollback = { [weak self] change in self?.rollback(change) }
        view.showDiff = { [weak self] _ in self?.showDiff() }
        gutter.addSubview(view)
        markerView = view
        view.changes = changes
        gutterFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: gutter,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let markerView = self.markerView, let gutter = markerView.superview else { return }
                let frame = Self.markerFrame(in: gutter)
                if markerView.frame != frame {
                    markerView.frame = frame
                }
            }
        }
    }

    private static func markerFrame(in gutter: NSView) -> NSRect {
        NSRect(
            x: gutter.bounds.width - GitGutterMarkerView.stripWidth,
            y: 0,
            width: GitGutterMarkerView.stripWidth,
            height: gutter.bounds.height
        )
    }

    private static func gutterView(in view: NSView?) -> GutterView? {
        guard let view else { return nil }
        if let gutter = view as? GutterView {
            return gutter
        }
        for subview in view.subviews {
            if let found = gutterView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func stopTracking() {
        refreshTask?.cancel()
        refreshTask = nil
        headTask?.cancel()
        headTask = nil
        memoryTask?.cancel()
        memoryTask = nil
        isTrackingRepository = false
        isUntrackedFile = false
        headText = nil
        apply(changes: [])
    }

    private func refreshFromGit() {
        refreshTask?.cancel()
        guard let manager = workspace?.sourceControlManager, let fileURL else {
            stopTracking()
            return
        }
        let relativePath = Self.relativePath(of: fileURL, from: manager.repositoryURL)
        guard !relativePath.isEmpty else {
            stopTracking()
            return
        }
        let gitClient = manager.gitClient
        refreshTask = Task { [weak self] in
            let snapshot = await Self.loadSnapshot(gitClient: gitClient, path: relativePath)
            guard !Task.isCancelled, let self else { return }
            apply(snapshot: snapshot)
            loadHeadText(gitClient: gitClient, path: relativePath)
        }
    }

    private func apply(snapshot: Snapshot) {
        isTrackingRepository = true
        isUntrackedFile = snapshot.untracked
        if snapshot.untracked, let textView = controller?.textView {
            apply(changes: GitLineChange.wholeFileAdded(lineCount: TextDiff.lines(in: textView.string).count))
        } else {
            apply(changes: snapshot.changes)
        }
    }

    private func loadHeadText(gitClient: GitClient, path: String) {
        headTask?.cancel()
        let quotedObject = GitClient.logGraphQuote("HEAD:./\(path)")
        headTask = Task { [weak self] in
            let headText = try? await gitClient.run("show \(quotedObject)")
            guard !Task.isCancelled, let self else { return }
            self.headText = headText
            refreshFromMemory()
        }
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.absoluteURL.standardizedFileURL.path(percentEncoded: false)
        let base = rootPath.hasSuffix("/") && rootPath.count > 1 ? String(rootPath.dropLast()) : rootPath
        let target = url.absoluteURL.standardizedFileURL.path(percentEncoded: false)
        let prefix = base.isEmpty ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return "" }
        return String(target.dropFirst(prefix.count))
    }

    @concurrent
    private static func loadSnapshot(gitClient: GitClient, path: String) async -> Snapshot {
        let quotedPath = GitClient.logGraphQuote(path)
        let diff = await output(of: "-c core.quotePath=false diff --no-color -U0 HEAD -- \(quotedPath)", in: gitClient)
        let parsed = GitLineChange.markers(inDiff: diff)
        guard parsed.isEmpty else {
            return Snapshot(changes: parsed, untracked: false)
        }
        let untrackedOutput = await output(
            of: "-c core.quotePath=false ls-files --others --exclude-standard -- \(quotedPath)",
            in: gitClient
        )
        let untracked = !untrackedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Snapshot(changes: [], untracked: untracked)
    }

    @concurrent
    private static func output(of command: String, in gitClient: GitClient) async -> String {
        guard let output = try? await gitClient.run(command) else { return "" }
        return output
    }

    private func scheduleMemoryRefresh() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            debounceTask = nil
            refreshFromMemory()
        }
    }

    private func refreshFromMemory() {
        guard isTrackingRepository, let textView = controller?.textView else { return }
        guard headText != nil || isUntrackedFile else { return }
        let currentText = textView.string
        let headText = self.headText
        memoryTask?.cancel()
        memoryTask = Task { [weak self] in
            let changes = await Self.markers(headText: headText, currentText: currentText)
            guard !Task.isCancelled, let self, self.isTrackingRepository else { return }
            apply(changes: changes)
        }
    }

    @concurrent
    private static func markers(headText: String?, currentText: String) async -> [GitLineChange] {
        guard let headText else {
            return GitLineChange.wholeFileAdded(lineCount: TextDiff.lines(in: currentText).count)
        }
        return GitLineChange.markers(from: TextDiff(left: headText, right: currentText))
    }

    private func apply(changes newChanges: [GitLineChange]) {
        guard changes != newChanges else { return }
        changes = newChanges
        markerView?.changes = newChanges
    }

    private func headLines() -> [String] {
        guard let headText else { return [] }
        return TextDiff.lines(in: headText)
    }

    private func previousContent(for change: GitLineChange) -> String? {
        guard let oldLines = change.oldLines else { return nil }
        let lines = headLines()
        let lower = max(1, oldLines.lowerBound)
        let upper = min(lines.count, oldLines.upperBound)
        guard lower <= upper else { return nil }
        return lines[(lower - 1)..<upper].joined(separator: "\n")
    }

    private func rollback(_ change: GitLineChange) {
        guard let textView = controller?.textView,
              let layoutManager = textView.layoutManager else {
            return
        }
        let text = textView.string as NSString
        let lineEnding = layoutManager.detectedLineEnding.rawValue

        let target: NSRange
        if let newLines = change.newLines {
            guard let first = layoutManager.textLineForIndex(newLines.lowerBound - 1),
                  let last = layoutManager.textLineForIndex(newLines.upperBound - 1) else {
                return
            }
            target = NSRange(location: first.range.location, length: last.range.upperBound - first.range.location)
        } else {
            let insertAt: Int
            if change.anchorLine <= 0 {
                insertAt = 0
            } else if let line = layoutManager.textLineForIndex(change.anchorLine - 1) {
                insertAt = line.range.upperBound
            } else {
                return
            }
            target = NSRange(location: insertAt, length: 0)
        }
        guard target.location <= text.length, NSMaxRange(target) <= text.length else { return }

        var replacement = rollbackText(for: change, lineEnding: lineEnding)
        if target.length == 0 {
            guard !replacement.isEmpty else { return }
            if target.location > 0, !Self.isLineEnding(text.character(at: target.location - 1)) {
                replacement = lineEnding + replacement
            }
            if target.location < text.length, !replacement.hasSuffix(lineEnding) {
                replacement += lineEnding
            }
        } else if !replacement.isEmpty {
            let current = text.substring(with: target)
            if (current.hasSuffix("\n") || current.hasSuffix("\r")), !replacement.hasSuffix(lineEnding) {
                replacement += lineEnding
            }
        }
        textView.replaceCharacters(in: target, with: replacement)
    }

    private func rollbackText(for change: GitLineChange, lineEnding: String) -> String {
        guard let oldLines = change.oldLines else { return "" }
        let lines = headLines()
        let lower = max(1, oldLines.lowerBound)
        let upper = min(lines.count, oldLines.upperBound)
        guard lower <= upper else { return "" }
        return lines[(lower - 1)..<upper].joined(separator: lineEnding)
    }

    private static func isLineEnding(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D
    }

    private func showDiff() {
        guard let fileURL, let workspace else { return }
        DiffViewerPresenter.showFileDiff(workspace: workspace, fileURL: fileURL, against: "HEAD")
    }
}
