import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CodeFileViewSessionTests {
    private func makeEditor(_ name: String = "file.swift") -> EditorInstance {
        EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/\(name)")))
    }

    @Test
    func sameEditorAndDocumentReuseTheSession() {
        let store = CodeFileViewSessionStore()
        let editor = makeEditor()
        let document = CodeFileDocument()

        let first = store.session(editorInstance: editor, codeFile: document)
        let second = store.session(editorInstance: editor, codeFile: document)

        #expect(first === second)
        #expect(first.treeSitterClient === second.treeSitterClient)
        #expect(first.coordinators.count == second.coordinators.count)
        #expect(zip(first.coordinators, second.coordinators).allSatisfy { $0 === $1 })
    }

    @Test
    func differentDocumentCreatesNewClientAndCoordinators() {
        let store = CodeFileViewSessionStore()
        let editor = makeEditor()
        let firstDocument = CodeFileDocument()
        let secondDocument = CodeFileDocument()

        let first = store.session(editorInstance: editor, codeFile: firstDocument)
        let second = store.session(editorInstance: editor, codeFile: secondDocument)

        #expect(first !== second)
        #expect(first.treeSitterClient !== second.treeSitterClient)
        #expect(zip(first.coordinators, second.coordinators).allSatisfy { $0 !== $1 })
    }

    @Test
    func differentEditorInstanceForTheSameDocumentCreatesNewSession() {
        let store = CodeFileViewSessionStore()
        let document = CodeFileDocument()

        let first = store.session(editorInstance: makeEditor("a.swift"), codeFile: document)
        let second = store.session(editorInstance: makeEditor("b.swift"), codeFile: document)

        #expect(first !== second)
        #expect(first.identity != second.identity)
    }

    @Test
    func separateStoresDoNotShareSessions() {
        let editor = makeEditor()
        let document = CodeFileDocument()

        let first = CodeFileViewSessionStore().session(editorInstance: editor, codeFile: document)
        let second = CodeFileViewSessionStore().session(editorInstance: editor, codeFile: document)

        #expect(first !== second)
        #expect(first.identity == second.identity)
    }

    @Test
    func sessionOwnsOneOfEachTextViewCoordinator() {
        let session = CodeFileViewSession(editorInstance: makeEditor(), codeFile: CodeFileDocument())

        #expect(session.coordinators.count == 13)
        #expect(session.coordinators.filter { $0 is GitBlameCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is EditorContextMenuCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is GitGutterCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is DiagnosticHighlightCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is InlayHintCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is OnTypeFormattingCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is SelectionRangeCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is FoldingCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is SignatureHelpCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is RecentLocationsCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is IndentGuideCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is EditorBackgroundCoordinator }.count == 1)
        #expect(session.coordinators.filter { $0 is CodeFileViewControllerReference }.count == 1)
        #expect(session.coordinators.contains { $0 is MarkdownTypingCoordinator } == false)
    }

    @Test
    func sessionBlameCoordinatorIsTheRegisteredOneForTheEditor() {
        let editor = makeEditor()
        let session = CodeFileViewSession(editorInstance: editor, codeFile: CodeFileDocument())

        let registered = GitBlameCoordinator.coordinator(for: editor)

        #expect(registered != nil)
        #expect(session.coordinators.contains { $0 === registered })
    }

    @Test
    func triggerCharactersAreAdoptedAtOnceWhileNoControllerExists() {
        let session = CodeFileViewSession(editorInstance: makeEditor(), codeFile: CodeFileDocument())
        let characters: Set<String> = [".", "("]

        let before = session.completionTriggerCharacters(requested: [])
        let adopted = session.completionTriggerCharacters(requested: characters)
        let repeated = session.completionTriggerCharacters(requested: characters)

        #expect(before.isEmpty)
        #expect(adopted == characters)
        #expect(repeated == characters)
    }

    @Test
    func adoptingTriggerCharactersDoesNotInvalidateTheView() {
        let store = CodeFileViewSessionStore()
        let session = store.session(editorInstance: makeEditor(), codeFile: CodeFileDocument())
        let generationBefore = store.generation

        _ = session.completionTriggerCharacters(requested: [".", "("])
        _ = session.completionTriggerCharacters(requested: [".", "("])

        #expect(store.generation == generationBefore)
    }

    @Test
    func identityDiffersPerObjectAndMatchesForTheSameObjects() {
        let editor = makeEditor()
        let document = CodeFileDocument()

        let same = CodeFileViewIdentity(editorInstance: editor, codeFile: document)
        let again = CodeFileViewIdentity(editorInstance: editor, codeFile: document)
        let other = CodeFileViewIdentity(editorInstance: editor, codeFile: CodeFileDocument())

        #expect(same == again)
        #expect(same.hashValue == again.hashValue)
        #expect(same != other)
    }
}
