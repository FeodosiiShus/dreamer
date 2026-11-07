import Combine
import Observation
import CodeEditSourceEditor

nonisolated struct CodeFileViewIdentity: Hashable, Sendable {
    let editorInstance: ObjectIdentifier
    let codeFile: ObjectIdentifier

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self.editorInstance = ObjectIdentifier(editorInstance)
        self.codeFile = ObjectIdentifier(codeFile)
    }
}

final class CodeFileViewControllerReference: TextViewCoordinator {
    private(set) weak var controller: TextViewController?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func destroy() {
        controller = nil
    }
}

final class CodeFileViewSession {
    let identity: CodeFileViewIdentity
    let treeSitterClient = TreeSitterClient()
    let coordinators: [TextViewCoordinator]

    private let editorInstance: EditorInstance
    private let codeFile: CodeFileDocument
    private let controllerReference: CodeFileViewControllerReference
    private let onCompletionTriggersApplied: () -> Void
    private var completionTriggerSync = CompletionTriggerSync()
    private var textUpdateSubscription: AnyCancellable?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        onCompletionTriggersApplied: @escaping () -> Void = {}
    ) {
        let controllerReference = CodeFileViewControllerReference()
        self.identity = CodeFileViewIdentity(editorInstance: editorInstance, codeFile: codeFile)
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self.controllerReference = controllerReference
        self.onCompletionTriggersApplied = onCompletionTriggersApplied
        self.coordinators = [
            GitBlameCoordinator(editorInstance: editorInstance, codeFile: codeFile),
            EditorContextMenuCoordinator(editorInstance: editorInstance, codeFile: codeFile),
            GitGutterCoordinator(codeFile: codeFile),
            DiagnosticHighlightCoordinator(codeFile: codeFile),
            InlayHintCoordinator(codeFile: codeFile),
            IndentGuideCoordinator(),
            EditorBackgroundCoordinator(),
            controllerReference
        ]
        self.textUpdateSubscription = codeFile.contentCoordinator.textUpdatePublisher
            .sink { [weak codeFile] _ in
                codeFile?.updateChangeCount(.changeDone)
            }
    }

    func completionTriggerCharacters(requested: Set<String>) -> Set<String> {
        let step = completionTriggerSync.request(requested, hasController: controllerReference.controller != nil)
        if step == .applyLater {
            Task { @MainActor [weak self] in
                self?.applyCompletionTriggerCharacters()
            }
        }
        return completionTriggerSync.applied
    }

    private func applyCompletionTriggerCharacters() {
        let characters = completionTriggerSync.commit()
        if let controller = controllerReference.controller,
           controller.configuration.peripherals.codeSuggestionTriggerCharacters != characters {
            controller.configuration.peripherals.codeSuggestionTriggerCharacters = characters
        }
        onCompletionTriggersApplied()
    }
}

@Observable
final class CodeFileViewSessionStore {
    @ObservationIgnored private var current: CodeFileViewSession?
    private(set) var generation = 0

    func session(editorInstance: EditorInstance, codeFile: CodeFileDocument) -> CodeFileViewSession {
        _ = generation
        let identity = CodeFileViewIdentity(editorInstance: editorInstance, codeFile: codeFile)
        if let current, current.identity == identity {
            return current
        }
        let session = CodeFileViewSession(editorInstance: editorInstance, codeFile: codeFile) { [weak self] in
            self?.generation += 1
        }
        current = session
        return session
    }
}
