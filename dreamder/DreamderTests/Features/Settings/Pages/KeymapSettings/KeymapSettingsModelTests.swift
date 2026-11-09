import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct KeymapSettingsModelTests {
    @MainActor
    struct Fixture {
        let model: KeymapSettingsModel
        let keymap: Keymap
        let monitoring: KeybindingsFakeMonitoring
        let defaults: UserDefaults
        let suiteName: String

        func tearDown() {
            removeIsolatedDefaults(defaults, suiteName: suiteName)
        }

        func press(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], characters: String? = nil) -> Bool {
            model.handleKeyDown(keyCode: keyCode, characters: characters, flags: flags)
        }
    }

    private func makeFixture() throws -> Fixture {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        let keymap = Keymap(defaults: defaults)
        let monitoring = KeybindingsFakeMonitoring()
        let model = KeymapSettingsModel(keymap: keymap, monitoring: monitoring)
        return Fixture(model: model, keymap: keymap, monitoring: monitoring, defaults: defaults, suiteName: suiteName)
    }

    private func makeKeyDown(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test
    func sectionsGroupEveryCommandInRegistryOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let sections = fixture.model.sections

        #expect(sections.map(\.group) == KeymapGroup.allCases)
        #expect(sections.flatMap(\.commands).sorted { $0.id < $1.id } == KeymapCommand.allCases.sorted { $0.id < $1.id })
        #expect(sections.first?.id == "Editor Actions")
        #expect(sections.allSatisfy { section in section.commands.allSatisfy { $0.group == section.group } })
    }

    @Test
    func queryFiltersByTitleAndGroupIgnoringCaseAndSurroundingSpaces() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.query = "  go to line "
        #expect(fixture.model.sections.flatMap(\.commands) == [.goToLine])

        fixture.model.query = "GIT"
        let git = fixture.model.sections.flatMap(\.commands)
        #expect(git.contains(.gitCommit))
        #expect(git.contains(.toolWindowGit))
        #expect(!git.contains(.save))

        fixture.model.query = "   "
        #expect(fixture.model.sections.flatMap(\.commands).count == KeymapCommand.allCases.count)

        fixture.model.query = "zzz-no-such-action"
        #expect(fixture.model.sections.isEmpty)
    }

    @Test
    func shortcutTextShowsGlyphsAndADashWhenUnassigned() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(fixture.model.shortcutText(for: .goToDeclaration) == "\u{2318}B")
        #expect(fixture.model.shortcutText(for: .quickDocumentation) == "\u{2303}J, F1")
        #expect(fixture.model.shortcutText(for: .searchEverywhere) == "\u{21E7}\u{21E7}")
        #expect(fixture.model.shortcutText(for: .goToClass) == "\u{2014}")
    }

    @Test
    func recordingReplacesTheShortcutAndStopsListening() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find)
        #expect(fixture.model.isRecording(.find))
        #expect(!fixture.model.isRecording(.save))
        #expect(fixture.model.recording == .command(.find, .replace))
        #expect(fixture.monitoring.localHandlers.count == 1)
        #expect(fixture.monitoring.localMatching == [.keyDown])

        #expect(fixture.press(16, [.option, .command]))

        #expect(fixture.keymap.shortcuts(for: .find) == [.stroke("y", [.option, .command])])
        #expect(fixture.model.recording == nil)
        #expect(!fixture.model.isRecording(.find))
        #expect(fixture.monitoring.removed == [1])
        #expect(fixture.model.pending == nil)
    }

    @Test
    func recordingInAddModeAppendsTheShortcut() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find, mode: .add)
        #expect(fixture.model.recording == .command(.find, .add))
        _ = fixture.press(16, [.option, .command])

        #expect(fixture.keymap.shortcuts(for: .find) == [.stroke("f", .command), .stroke("y", [.option, .command])])
    }

    @Test
    func escapeCancelsRecordingWithoutChangingAnything() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find)
        #expect(fixture.press(53))

        #expect(fixture.model.recording == nil)
        #expect(fixture.keymap.shortcuts(for: .find) == KeymapCommand.find.defaultShortcuts)
        #expect(fixture.monitoring.removed == [1])
    }

    @Test
    func backspaceWhileRecordingClearsTheCommandsShortcuts() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.quickDocumentation)
        #expect(fixture.press(51))

        #expect(fixture.keymap.shortcuts(for: .quickDocumentation).isEmpty)
        #expect(fixture.keymap.keyboardShortcut(for: .quickDocumentation) == nil)
        #expect(fixture.model.recording == nil)
    }

    @Test
    func keysWithoutAMenuModifierAreRejectedAndRecordingContinues() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find)
        #expect(fixture.model.recordingHint == "Press the shortcut. Esc cancels, \u{232B} clears.")
        #expect(fixture.press(11))

        #expect(fixture.model.rejectedStroke == KeyStroke("b"))
        #expect(fixture.model.recording == .command(.find, .replace))
        #expect(fixture.model.recordingHint == "B needs \u{2318}, \u{2303} or \u{2325}. Press another shortcut.")
        #expect(fixture.keymap.shortcuts(for: .find) == KeymapCommand.find.defaultShortcuts)

        #expect(fixture.press(16, .command))
        #expect(fixture.model.rejectedStroke == nil)
        #expect(fixture.model.recordingHint == nil)
        #expect(fixture.keymap.shortcuts(for: .find) == [.stroke("y", .command)])
    }

    @Test
    func unrecognizedKeysAreSwallowedWhileRecording() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find)

        #expect(fixture.press(0xFFF, .command, characters: nil))
        #expect(fixture.model.recording == .command(.find, .replace))
    }

    @Test
    func keysAreNotConsumedWhenNothingIsRecording() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(!fixture.press(11, .command))
        #expect(fixture.model.recordingHint == nil)
    }

    @Test
    func findByShortcutFiltersTheListToTheCommandsUsingIt() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginFilterRecording()
        #expect(fixture.model.recording == .filter)
        #expect(!fixture.model.isRecording(.find))
        #expect(fixture.press(11, .command))

        #expect(fixture.model.shortcutFilter == .stroke("b", .command))
        #expect(fixture.model.recording == nil)
        #expect(fixture.model.sections.flatMap(\.commands) == [.goToDeclaration])

        fixture.model.query = "Declaration"
        #expect(fixture.model.sections.flatMap(\.commands) == [.goToDeclaration])
        fixture.model.query = "Save"
        #expect(fixture.model.sections.isEmpty)

        fixture.model.query = ""
        fixture.model.clearShortcutFilter()
        #expect(fixture.model.shortcutFilter == nil)
        #expect(fixture.model.sections.flatMap(\.commands).count == KeymapCommand.allCases.count)
    }

    @Test
    func backspaceWhileRecordingTheFilterClearsIt() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginFilterRecording()
        _ = fixture.press(11, .command)
        fixture.model.beginFilterRecording()
        _ = fixture.press(51)

        #expect(fixture.model.shortcutFilter == nil)
        #expect(fixture.model.recording == nil)
    }

    @Test
    func escapeWhileRecordingTheFilterKeepsTheCurrentFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginFilterRecording()
        _ = fixture.press(11, .command)
        fixture.model.beginFilterRecording()
        _ = fixture.press(53)

        #expect(fixture.model.shortcutFilter == .stroke("b", .command))
    }

    @Test
    func assigningATakenShortcutRaisesAConflictInsteadOfApplyingIt() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)

        let pending = try #require(fixture.model.pending)
        #expect(pending.command == .save)
        #expect(pending.shortcut == .stroke("b", .command))
        #expect(pending.conflicts == [.goToDeclaration])
        #expect(pending.message == "\u{2318}B is already assigned to Go to Declaration or Usages")
        #expect(fixture.keymap.shortcuts(for: .save) == KeymapCommand.save.defaultShortcuts)
        #expect(fixture.model.recording == nil)
    }

    @Test
    func conflictMessagesListEveryConflictingCommand() {
        let pending = PendingKeymapAssignment(
            command: .save,
            shortcut: .stroke("b", [.shift, .command]),
            mode: .add,
            conflicts: [.goToTypeDeclaration, .goToDeclaration]
        )

        #expect(
            pending.message
                == "\u{21E7}\u{2318}B is already assigned to Go to Type Declaration, Go to Declaration or Usages"
        )
    }

    @Test
    func cancellingAConflictLeavesBothBindingsUntouched() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)
        fixture.model.resolvePending(.cancel)

        #expect(fixture.model.pending == nil)
        #expect(fixture.keymap.shortcuts(for: .save) == KeymapCommand.save.defaultShortcuts)
        #expect(fixture.keymap.shortcuts(for: .goToDeclaration) == KeymapCommand.goToDeclaration.defaultShortcuts)
    }

    @Test
    func leavingAConflictAssignsTheShortcutToBothCommandsAndFlagsThem() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)
        fixture.model.resolvePending(.leave)

        #expect(fixture.keymap.shortcuts(for: .save) == [.stroke("b", .command)])
        #expect(fixture.keymap.shortcuts(for: .goToDeclaration) == [.stroke("b", .command)])
        #expect(fixture.model.conflicts(of: .save) == [.goToDeclaration])
        #expect(fixture.model.conflicts(of: .goToDeclaration) == [.save])
    }

    @Test
    func removingTheOtherBindingResolvesTheConflict() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)
        fixture.model.resolvePending(.remove)

        #expect(fixture.keymap.shortcuts(for: .save) == [.stroke("b", .command)])
        #expect(fixture.keymap.shortcuts(for: .goToDeclaration).isEmpty)
        #expect(fixture.model.conflicts(of: .save).isEmpty)
        #expect(fixture.model.pending == nil)
    }

    @Test
    func removingInAddModeKeepsTheCommandsOwnShortcuts() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save, mode: .add)
        _ = fixture.press(11, .command)
        fixture.model.resolvePending(.remove)

        #expect(fixture.keymap.shortcuts(for: .save) == [.stroke("s", .command), .stroke("b", .command)])
        #expect(fixture.keymap.shortcuts(for: .goToDeclaration).isEmpty)
    }

    @Test
    func resolvingWithoutAPendingAssignmentDoesNothing() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.resolvePending(.remove)

        #expect(fixture.keymap.overrides.isEmpty)
    }

    @Test
    func startingToRecordDiscardsAPendingConflict() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)
        #expect(fixture.model.pending != nil)

        fixture.model.beginRecording(.find)

        #expect(fixture.model.pending == nil)
    }

    @Test
    func resetAndRemoveForwardToTheKeymap() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.keymap.replaceShortcuts(of: .find, with: .stroke("y", .command))
        fixture.model.reset(.find)
        #expect(!fixture.keymap.isModified(.find))

        fixture.model.remove(.stroke("j", .control), from: .quickDocumentation)
        #expect(fixture.keymap.shortcuts(for: .quickDocumentation) == [.stroke(KeyNames.f1)])
    }

    @Test
    func resetAllRestoresEverythingAndDropsAPendingConflict() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.keymap.replaceShortcuts(of: .find, with: .stroke("y", .command))
        fixture.model.beginRecording(.save)
        _ = fixture.press(11, .command)
        fixture.model.resetAll()

        #expect(fixture.keymap.overrides.isEmpty)
        #expect(fixture.model.pending == nil)
    }

    @Test
    func theInstalledMonitorConsumesKeyDownsWhileRecordingAndPassesThemOtherwise() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let event = try makeKeyDown(16, [.option, .command], characters: "y")

        fixture.model.beginRecording(.find)
        let handler = try #require(fixture.monitoring.localHandlers.last)

        #expect(handler(event) == nil)
        #expect(fixture.keymap.shortcuts(for: .find) == [.stroke("y", [.option, .command])])
        #expect(handler(event) === event)
    }

    @Test
    func startingAgainReplacesTheMonitorAndCancellingRemovesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.model.beginRecording(.find)
        fixture.model.beginRecording(.save)
        #expect(fixture.monitoring.localHandlers.count == 2)
        #expect(fixture.monitoring.removed == [1])

        fixture.model.cancelRecording()
        fixture.model.cancelRecording()

        #expect(fixture.monitoring.removed == [1, 2])
        #expect(fixture.model.recording == nil)
    }

    @Test
    func releasingTheModelRemovesItsMonitorAndClearsTheRecordingFlag() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let monitoring = KeybindingsFakeMonitoring()
        let keymap = Keymap(defaults: defaults)
        var model: KeymapSettingsModel? = KeymapSettingsModel(keymap: keymap, monitoring: monitoring)

        model?.beginRecording(.find)
        #expect(keymap.isRecording)
        model = nil
        await Task.yield()

        #expect(monitoring.removed == [1])
        #expect(!keymap.isRecording)
    }

    @Test
    func theKeymapKnowsWhileARecordingIsActive() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(!fixture.keymap.isRecording)
        fixture.model.beginFilterRecording()
        #expect(fixture.keymap.isRecording)
        _ = fixture.press(53)
        #expect(!fixture.keymap.isRecording)
    }
}
