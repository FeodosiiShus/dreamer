import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct UndoManagerRegistrationModelsCoverageTests {
    private let registrar = UndoManagerRegistration()
    private let url = URL(filePath: "/fake/dir/file.txt")

    @Test
    func managerIfExistsOnlyReturnsManagersThatWereCreated() {
        #expect(registrar.managerIfExists(forFile: url) == nil)

        let created = registrar.manager(forFile: url)

        #expect(registrar.managerIfExists(forFile: url) === created)
        #expect(registrar.managerIfExists(forFile: URL(filePath: "/fake/dir/other.txt")) == nil)
    }

    @Test
    func managersForTheSameFileAreSharedBetweenFileAndURLLookups() {
        let file = CEWorkspaceFile(url: url)

        #expect(registrar.manager(forFile: file) === registrar.manager(forFile: url))
    }

    @Test
    func updatedFilesWithoutADocumentLoseTheirUndoManager() {
        let file = CEWorkspaceFile(url: url)
        let kept = CEWorkspaceFile(url: URL(filePath: "/fake/dir/kept.txt"))
        _ = registrar.manager(forFile: file)
        let keptManager = registrar.manager(forFile: kept)

        registrar.fileManagerUpdated(updatedItems: [file])

        #expect(registrar.managerIfExists(forFile: url) == nil)
        #expect(registrar.managerIfExists(forFile: kept.url) === keptManager)
    }

    @Test
    func tabIDsAreDerivedFromTheirPayload() {
        let identifier = UUID()

        #expect(EditorTabID.codeEditor("/fake/a.txt").id == "codeEditor_/fake/a.txt")
        #expect(EditorTabID.extensionInstallation(identifier).id == "extensionInstallation_\(identifier.uuidString)")
        #expect(EditorTabID.codeEditor("x") != EditorTabID.extensionInstallation(identifier))
        #expect(CEWorkspaceFile(url: url).tabID == .codeEditor(CEWorkspaceFile(url: url).id))
    }
}
