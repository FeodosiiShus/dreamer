import AppKit
import Combine
import Observation
import CodeEditSourceEditor
import CodeEditTextView

final class GitBlameCoordinator: TextViewCoordinator {
    private final class WeakBox {
        weak var coordinator: GitBlameCoordinator?

        init(_ coordinator: GitBlameCoordinator) {
            self.coordinator = coordinator
        }
    }

    private static var registry: [ObjectIdentifier: WeakBox] = [:]

    static func coordinator(for editorInstance: EditorInstance) -> GitBlameCoordinator? {
        guard let coordinator = registry[ObjectIdentifier(editorInstance)]?.coordinator,
              coordinator.editorInstance === editorInstance else { return nil }
        return coordinator
    }

    private weak var editorInstance: EditorInstance?
    private let codeFile: CodeFileDocument
    private let reloadDebounce: TimeInterval
    private let documentEditedChanges: AsyncStream<Bool>?
    private weak var controller: TextViewController?
    private weak var textView: TextView?
    private weak var workspace: WorkspaceDocument?

    private var inlineView: GitBlameInlineView?
    private var annotationView: GitBlameAnnotationView?
    private var displayedInlineText: String?
    private var cancellables = Set<AnyCancellable>()
    private var repositoryObservation: Task<Void, Never>?
    private var documentEditedObservation: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isObservingScroll = false
    private var blameLines: [Int: GitBlameLine] = [:]
    private var caretLine = 1
    private var generation = 0
    private var isSubscribed = false

    private lazy var refreshCoalescer = MainTurnCoalescer { [weak self] in
        self?.refreshViews()
    }

    private(set) var isAnnotating = false

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        reloadDebounce: TimeInterval = 2.5,
        documentEditedChanges: AsyncStream<Bool>? = nil
    ) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self.reloadDebounce = reloadDebounce
        self.documentEditedChanges = documentEditedChanges
        register()
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        repositoryObservation?.cancel()
        documentEditedObservation?.cancel()
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        self.textView = controller.textView
        caretLine = max(controller.cursorPositions.first?.start.line ?? 1, 1)
        register()
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
        refreshCoalescer.request()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        if let line = newPositions.first?.start.line, line > 0 {
            caretLine = line
        }
        refreshCoalescer.request()
    }

    func destroy() {
        generation += 1
        isSubscribed = false
        cancellables.removeAll()
        documentEditedObservation?.cancel()
        documentEditedObservation = nil
        repositoryObservation?.cancel()
        repositoryObservation = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        isObservingScroll = false
        inlineView?.removeFromSuperview()
        inlineView = nil
        displayedInlineText = nil
        annotationView?.removeFromSuperview()
        annotationView = nil
        unregister()
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

    private func register() {
        guard let editorInstance else { return }
        let identifier = ObjectIdentifier(editorInstance)
        Self.registry = Self.registry.filter { $0.value.coordinator != nil }
        Self.registry[identifier] = WeakBox(self)
    }

    private func unregister() {
        guard let editorInstance else { return }
        let identifier = ObjectIdentifier(editorInstance)
        if Self.registry[identifier]?.coordinator === self {
            Self.registry.removeValue(forKey: identifier)
        }
    }

    private func installViews(controller: TextViewController) {
        guard let textView = controller.textView,
              let scrollView = controller.scrollView else { return }

        if inlineView == nil {
            let view = GitBlameInlineView(frame: textView.bounds)
            view.anchorProvider = { [weak self] in
                self?.inlineAnchor()
            }
            textView.addSubview(view)
            inlineView = view
            displayedInlineText = nil
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.inlineView?.matchSuperviewBounds()
                    }
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: InlayHintCoordinator.hintsDidChangeNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.inlineView?.needsDisplay = true
                    }
                }
            )
        }

        if annotationView == nil {
            let view = GitBlameAnnotationView(textView: textView)
            view.isHidden = !isAnnotating
            view.onSelectCommit = { [weak self] in
                self?.showGitToolWindow()
            }
            view.frame = NSRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.addSubview(view)
            annotationView = view
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.annotationView?.matchSuperviewBounds()
                    }
                }
            )
        }

        annotationView?.update(lines: blameLines)
        refreshCoalescer.request()
    }

    private func observeEditor(controller: TextViewController) {
        guard !isObservingScroll else { return }
        isObservingScroll = true
        observers.append(
            NotificationCenter.default.addObserver(
                forName: TextViewController.scrollPositionDidUpdateNotification,
                object: controller,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshCoalescer.request()
                }
            }
        )
    }

    private func subscribeToDocument() {
        guard !isSubscribed else { return }
        isSubscribed = true

        codeFile.contentCoordinator.textUpdatePublisher
            .debounce(for: .seconds(reloadDebounce), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        let editedChanges = documentEditedChanges ?? Self.editedChanges(of: codeFile)
        documentEditedObservation = Task { [weak self] in
            for await isEdited in editedChanges where !isEdited {
                self?.reload()
            }
        }

        if let sourceControlManager = workspace?.sourceControlManager {
            repositoryObservation = Task { [weak self, weak sourceControlManager] in
                let states = Observations { [weak sourceControlManager] in
                    sourceControlManager?.isGitRepository ?? false
                }
                for await isRepository in states {
                    guard let self else { return }
                    if isRepository {
                        reload()
                    } else {
                        apply(lines: [])
                    }
                }
            }
        }
    }

    private static func editedChanges(of codeFile: CodeFileDocument) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let observation = Task { @MainActor in
                var isFirst = true
                for await isEdited in Observations({ codeFile.isEdited }) {
                    if isFirst {
                        isFirst = false
                        continue
                    }
                    continuation.yield(isEdited)
                }
            }
            continuation.onTermination = { _ in observation.cancel() }
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
        let client = workspace?.sourceControlManager?.gitClient

        Task {
            let parsed = await Self.blame(for: url, using: client)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.apply(lines: parsed)
            }
        }
    }

    private func apply(lines: [GitBlameLine]) {
        var byLine: [Int: GitBlameLine] = [:]
        for line in lines {
            byLine[line.line] = line
        }
        blameLines = byLine
        annotationView?.update(lines: byLine)
        refreshCoalescer.request()
    }

    private func refreshViews() {
        guard controller != nil else { return }
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

    private func inlineAnchor() -> CGRect? {
        guard let layoutManager = textView?.layoutManager,
              caretLine <= layoutManager.lineCount,
              let position = layoutManager.textLineForIndex(caretLine - 1) else {
            return nil
        }
        if position.range.length > 0 {
            return layoutManager.rectForOffset(position.range.max - 1)
        }
        return layoutManager.rectForOffset(position.range.location)
    }

    private func refreshInlineBlame() {
        guard let inlineView else { return }
        let text = blameLines[caretLine].map(Self.inlineText(for:))
        if displayedInlineText != text {
            inlineView.setText(text)
            displayedInlineText = text
        }
        inlineView.matchSuperviewBounds()
        inlineView.needsDisplay = true
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

    private static func blame(for url: URL, using client: GitClient?) async -> [GitBlameLine] {
        guard let client,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        let path = url.path(percentEncoded: false)
        guard let output = try? await client.run(arguments: ["blame", "--porcelain", "--", path]) else { return [] }
        return GitBlameParser.parse(output)
    }
}
