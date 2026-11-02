import AppKit
import Combine
import CodeEditSourceEditor
import CodeEditTextView

final class GitBlameCoordinator: TextViewCoordinator {
    private final class WeakBox {
        weak var coordinator: GitBlameCoordinator?

        init(_ coordinator: GitBlameCoordinator) {
            self.coordinator = coordinator
        }
    }

    private static var coordinators: [ObjectIdentifier: WeakBox] = [:]

    static func coordinator(for editorInstance: EditorInstance) -> GitBlameCoordinator? {
        coordinators[ObjectIdentifier(editorInstance)]?.coordinator
    }

    private weak var editorInstance: EditorInstance?
    private let codeFile: CodeFileDocument
    private weak var controller: TextViewController?
    private weak var textView: TextView?
    private weak var workspace: WorkspaceDocument?

    private var inlineView: GitBlameInlineView?
    private var annotationView: GitBlameAnnotationView?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var blameLines: [Int: GitBlameLine] = [:]
    private var caretLine = 1
    private var generation = 0
    private var isSubscribed = false

    private(set) var isAnnotating = false

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        Self.coordinators = Self.coordinators.filter { $0.value.coordinator != nil }
        Self.coordinators[ObjectIdentifier(editorInstance)] = WeakBox(self)
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        self.textView = controller.textView
        caretLine = max(controller.cursorPositions.first?.start.line ?? 1, 1)
    }

    func controllerDidAppear(controller: TextViewController) {
        if workspace == nil {
            workspace = codeFile.findWorkspace()
        }
        installViews(controller: controller)
        observeEditor(controller: controller)
        subscribeToDocument()
        reload()
    }

    func textViewDidChangeText(controller: TextViewController) {
        blameLines = [:]
        annotationView?.update(lines: [:])
        refreshInlineBlame()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        if let line = newPositions.first?.start.line, line > 0 {
            caretLine = line
        }
        refreshInlineBlame()
    }

    func destroy() {
        generation += 1
        cancellables.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        inlineView?.removeFromSuperview()
        inlineView = nil
        annotationView?.removeFromSuperview()
        annotationView = nil
        if let editorInstance {
            let identifier = ObjectIdentifier(editorInstance)
            if Self.coordinators[identifier]?.coordinator === self {
                Self.coordinators.removeValue(forKey: identifier)
            }
        }
        controller = nil
        textView = nil
    }

    func toggleAnnotate() {
        isAnnotating.toggle()
        annotationView?.isHidden = !isAnnotating
        annotationView?.update(lines: blameLines)
    }

    private var fileURL: URL? {
        editorInstance?.file.url ?? codeFile.fileURL
    }

    private func installViews(controller: TextViewController) {
        guard let textView = controller.textView,
              let scrollView = controller.scrollView else { return }

        if inlineView == nil {
            let view = GitBlameInlineView()
            view.isHidden = true
            textView.addSubview(view)
            inlineView = view
        }

        if annotationView == nil {
            let view = GitBlameAnnotationView(textView: textView)
            view.isHidden = !isAnnotating
            view.onSelectCommit = { [weak self] in
                self?.showGitToolWindow()
            }
            view.autoresizingMask = [.width, .height]
            view.frame = NSRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.addSubview(view)
            annotationView = view
        }

        annotationView?.update(lines: blameLines)
        refreshInlineBlame()
    }

    private func observeEditor(controller: TextViewController) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: TextViewController.scrollPositionDidUpdateNotification,
                object: controller,
                queue: .main
            ) { [weak self] _ in
                self?.refreshViews()
            }
        )
        if let textView = controller.textView {
            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] _ in
                    self?.refreshViews()
                }
            )
        }
    }

    private func subscribeToDocument() {
        guard !isSubscribed else { return }
        isSubscribed = true

        codeFile.contentCoordinator.textUpdatePublisher
            .debounce(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        codeFile.isDocumentEditedPublisher
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        if let sourceControlManager = workspace?.sourceControlManager {
            sourceControlManager.$isGitRepository
                .receive(on: RunLoop.main)
                .sink { [weak self] isRepository in
                    guard let self else { return }
                    if isRepository {
                        self.reload()
                    } else {
                        self.apply(lines: [])
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func reload() {
        guard let url = fileURL else { return }
        if let sourceControlManager = workspace?.sourceControlManager,
           !sourceControlManager.isGitRepository {
            return
        }
        generation += 1
        let generation = generation
        let directory = repositoryDirectory(for: url)

        Task {
            let parsed = await Self.blame(for: url, in: directory)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.apply(lines: parsed)
            }
        }
    }

    private func repositoryDirectory(for url: URL) -> URL {
        if let repository = workspace?.sourceControlManager?.repositoryURL {
            return repository
        }
        return url.deletingLastPathComponent()
    }

    private func apply(lines: [GitBlameLine]) {
        var byLine: [Int: GitBlameLine] = [:]
        for line in lines {
            byLine[line.line] = line
        }
        blameLines = byLine
        annotationView?.update(lines: byLine)
        refreshInlineBlame()
    }

    private func refreshViews() {
        syncAnnotationFrame()
        inlineView?.needsDisplay = true
        annotationView?.needsDisplay = true
        refreshInlineBlame()
    }

    private func syncAnnotationFrame() {
        guard let annotationView, let scrollView = controller?.scrollView else { return }
        let target = NSRect(origin: .zero, size: scrollView.bounds.size)
        if annotationView.frame != target {
            annotationView.frame = target
        }
    }

    private func refreshInlineBlame() {
        guard let inlineView, let textView = textView else { return }
        guard let blame = blameLines[caretLine] else {
            inlineView.isHidden = true
            return
        }
        guard let layoutManager = textView.layoutManager else {
            inlineView.isHidden = true
            return
        }
        guard caretLine <= layoutManager.lineCount,
              let position = layoutManager.textLineForIndex(caretLine - 1) else {
            inlineView.isHidden = true
            return
        }

        let anchor: CGRect? = if position.range.length > 0 {
            layoutManager.rectForOffset(position.range.max - 1)
        } else {
            layoutManager.rectForOffset(position.range.location)
        }
        guard let anchor else {
            inlineView.isHidden = true
            return
        }

        inlineView.setText(Self.inlineText(for: blame))
        inlineView.frame.origin = NSPoint(
            x: anchor.maxX + Islands.smallFontSize * 3,
            y: anchor.minY + max((anchor.height - inlineView.frame.height) / 2, 0)
        )
        inlineView.isHidden = false
    }

    private func showGitToolWindow() {
        codeFile.findWorkspace()?.toolWindowManager.show(.git)
    }

    private static func inlineText(for line: GitBlameLine) -> String {
        guard !line.isUncommitted else { return "You, uncommitted" }
        let date = GitBlameRelativeDate.string(for: line.authorDate)
        guard !line.summary.isEmpty else { return "\(line.author), \(date)" }
        return "\(line.author), \(date) • \(line.summary)"
    }

    private static func blame(for url: URL, in directory: URL) async -> [GitBlameLine] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        let client = GitClient(directoryURL: directory, shellClient: ShellClient.live())
        let path = GitClient.logGraphQuote(url.path(percentEncoded: false))
        guard let output = try? await client.run("blame --porcelain -- \(path)") else { return [] }
        return GitBlameParser.parse(output)
    }
}
