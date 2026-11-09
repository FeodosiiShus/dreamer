import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct UndoManagerRegistrationRemovalTests {
    private let registration = UndoManagerRegistration()

    @Test
    func removingAManagerThatDoesNotExistIsHarmless() {
        let url = URL(filePath: "/fake/dir/missing.txt")

        registration.removeManager(forFile: url)

        #expect(registration.managerIfExists(forFile: url) == nil)
    }

    @Test
    func removingAManagerOnlyDropsThatFilesManager() {
        let removed = URL(filePath: "/fake/dir/removed.txt")
        let kept = URL(filePath: "/fake/dir/kept.txt")
        let removedManager = registration.manager(forFile: removed)
        let keptManager = registration.manager(forFile: kept)

        registration.removeManager(forFile: removed)

        #expect(registration.managerIfExists(forFile: removed) == nil)
        #expect(registration.managerIfExists(forFile: kept) === keptManager)
        #expect(registration.manager(forFile: removed) !== removedManager)
    }
}
