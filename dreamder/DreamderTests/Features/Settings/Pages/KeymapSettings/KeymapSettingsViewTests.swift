import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct KeymapSettingsViewTests {
    @MainActor
    struct Session {
        let model: KeymapSettingsModel
        let keymap: Keymap
        let monitoring: KeybindingsFakeMonitoring
        let defaults: UserDefaults
        let suiteName: String

        func tearDown() {
            removeIsolatedDefaults(defaults, suiteName: suiteName)
        }
    }

    private let pageSize = NSSize(width: 720, height: 520)

    private func makeSession() throws -> Session {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        let keymap = Keymap(defaults: defaults)
        let monitoring = KeybindingsFakeMonitoring()
        let model = KeymapSettingsModel(keymap: keymap, monitoring: monitoring)
        return Session(model: model, keymap: keymap, monitoring: monitoring, defaults: defaults, suiteName: suiteName)
    }

    private func hostPage(_ session: Session) -> HostedView {
        HostedViewFixture.host(size: pageSize) {
            KeymapSettingsView(model: session.model)
        }
    }

    @Test
    func theDefaultPageRendersTheGroupedList() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let hosted = hostPage(session)
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(80))

        #expect(hosted.renders())
    }

    @Test
    func theDefaultInitializerBuildsItsOwnModel() async throws {
        let hosted = HostedViewFixture.host(size: pageSize) {
            KeymapSettingsView()
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(80))

        #expect(hosted.renders())
    }

    @Test
    func filteringByTextChangesTheRenderedRows() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let hosted = hostPage(session)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(80))
        let everything = hosted.snapshot()

        session.model.query = "Line"
        try await hosted.settle(.milliseconds(80))
        let lines = hosted.snapshot()

        session.model.query = "zzz-no-such-action"
        try await hosted.settle(.milliseconds(80))
        let none = hosted.snapshot()

        #expect(HostedView.pixelsDiffer(everything, lines))
        #expect(HostedView.pixelsDiffer(lines, none))
        #expect(session.model.sections.isEmpty)
        #expect(none != nil)
    }

    @Test
    func recordingShowsTheHintFooterAndTheRecordingField() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.model.query = "Line"
        let hosted = hostPage(session)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(80))
        let idle = hosted.snapshot()

        session.model.beginRecording(.deleteLine)
        try await hosted.settle(.milliseconds(80))
        let recording = hosted.snapshot()
        _ = session.model.handleKeyDown(keyCode: 11, characters: nil, flags: [])
        try await hosted.settle(.milliseconds(80))
        let rejected = hosted.snapshot()

        #expect(HostedView.pixelsDiffer(idle, recording))
        #expect(HostedView.pixelsDiffer(recording, rejected))
        #expect(session.model.recordingHint != nil)
    }

    @Test
    func recordingAShortcutUpdatesTheRowsAndResetRestoresThem() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.model.query = "Delete Line"
        let hosted = hostPage(session)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(80))
        let original = hosted.snapshot()

        session.model.beginRecording(.deleteLine)
        _ = session.model.handleKeyDown(keyCode: 16, characters: nil, flags: [.option, .command])
        try await hosted.settle(.milliseconds(80))
        let modified = hosted.snapshot()

        session.model.reset(.deleteLine)
        try await hosted.settle(.milliseconds(80))
        let restored = hosted.snapshot()

        #expect(session.keymap.shortcuts(for: .deleteLine) == KeymapCommand.deleteLine.defaultShortcuts)
        #expect(HostedView.pixelsDiffer(original, modified))
        #expect(HostedView.pixelsDiffer(modified, restored))
    }

    @Test
    func conflictsShowANoteOnBothRowsAndAResolutionRowWhilePending() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.model.query = "Line"
        let hosted = hostPage(session)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(80))
        let clean = hosted.snapshot()

        session.model.beginRecording(.deleteLine)
        _ = session.model.handleKeyDown(keyCode: 2, characters: nil, flags: [.command])
        try await hosted.settle(.milliseconds(80))
        let pending = hosted.snapshot()
        session.model.resolvePending(.leave)
        try await hosted.settle(.milliseconds(80))
        let flagged = hosted.snapshot()
        session.model.beginRecording(.deleteLine)
        _ = session.model.handleKeyDown(keyCode: 2, characters: nil, flags: [.command])
        session.model.resolvePending(.remove)
        try await hosted.settle(.milliseconds(80))

        #expect(HostedView.pixelsDiffer(clean, pending))
        #expect(HostedView.pixelsDiffer(pending, flagged))
        #expect(session.keymap.shortcuts(for: .duplicateLine).isEmpty)
        #expect(session.model.conflicts(of: .deleteLine).isEmpty)
    }

    @Test
    func theShortcutFilterChipAndRecordingButtonRender() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let hosted = hostPage(session)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(80))
        let idle = hosted.snapshot()

        session.model.beginFilterRecording()
        try await hosted.settle(.milliseconds(80))
        let recording = hosted.snapshot()
        _ = session.model.handleKeyDown(keyCode: 11, characters: nil, flags: [.command])
        try await hosted.settle(.milliseconds(80))
        let filtered = hosted.snapshot()

        #expect(HostedView.pixelsDiffer(idle, recording))
        #expect(HostedView.pixelsDiffer(recording, filtered))
        #expect(session.model.sections.flatMap(\.commands) == [.goToDeclaration])
    }

    @Test
    func theToolbarEnablesResetAllOnlyWhenSomethingChanged() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let hosted = HostedViewFixture.host(size: NSSize(width: 720, height: 60)) {
            KeymapToolbar(model: session.model)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))
        let untouched = hosted.snapshot()

        session.keymap.replaceShortcuts(of: .find, with: .stroke("y", .command))
        try await hosted.settle(.milliseconds(60))

        #expect(HostedView.pixelsDiffer(untouched, hosted.snapshot()))
    }

    @Test
    func rowMenuListsRemovalsForEveryShortcutAndResetsWhenModified() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let menu = HostedViewFixture.host(size: NSSize(width: 320, height: 200)) {
            KeymapRowMenu(model: session.model, command: .quickDocumentation)
        }
        defer { menu.close() }
        try await menu.settle(.milliseconds(60))
        let unmodified = menu.snapshot()

        session.keymap.addShortcut(.stroke("q", .control), to: .quickDocumentation)
        try await menu.settle(.milliseconds(60))

        #expect(HostedView.pixelsDiffer(unmodified, menu.snapshot()))
    }

    @Test
    func rowMenuActionsStartRecordingInAddModeAndReset() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let menu = KeymapRowMenu(model: session.model, command: .find)

        menu.add()
        #expect(session.model.recording == .command(.find, .add))

        session.keymap.replaceShortcuts(of: .find, with: .stroke("y", .command))
        menu.reset()
        #expect(!session.keymap.isModified(.find))
    }

    @Test
    func rowMenuRemoveItemDropsTheShortcutFromTheKeymap() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let extra = Shortcut.stroke("y", .command)
        session.keymap.addShortcut(extra, to: .find)
        let menu = CommandsACoverageSupport.host {
            KeymapRowMenu(model: session.model, command: .find)
        }
        defer { menu.close() }

        try menu.click(titled: "Remove \(extra.displayText)")

        #expect(!session.keymap.shortcuts(for: .find).contains(extra))
    }

    @Test
    func theShortcutFieldStartsRecordingInReplaceMode() throws {
        let session = try makeSession()
        defer { session.tearDown() }

        KeymapShortcutField(model: session.model, command: .save).record()

        #expect(session.model.recording == .command(.save, .replace))
    }

    @Test
    func theRowResetButtonRestoresTheDefaultShortcut() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.keymap.replaceShortcuts(of: .save, with: .stroke("y", .command))

        KeymapCommandRow(model: session.model, command: .save).reset()

        #expect(!session.keymap.isModified(.save))
    }

    @Test
    func theConflictRowButtonsResolveThePendingAssignment() throws {
        let session = try makeSession()
        defer { session.tearDown() }

        func raiseConflict() throws -> PendingKeymapAssignment {
            session.model.beginRecording(.save)
            _ = session.model.handleKeyDown(keyCode: 11, characters: nil, flags: [.command])
            return try #require(session.model.pending)
        }

        var pending = try raiseConflict()
        KeymapConflictRow(model: session.model, pending: pending).cancel()
        #expect(session.model.pending == nil)
        #expect(session.keymap.shortcuts(for: .save) == KeymapCommand.save.defaultShortcuts)

        pending = try raiseConflict()
        KeymapConflictRow(model: session.model, pending: pending).leave()
        #expect(session.model.conflicts(of: .save) == [.goToDeclaration])

        session.keymap.resetAll()
        pending = try raiseConflict()
        KeymapConflictRow(model: session.model, pending: pending).remove()
        #expect(session.keymap.shortcuts(for: .goToDeclaration).isEmpty)
        #expect(session.keymap.shortcuts(for: .save) == [.stroke("b", .command)])
    }

    @Test
    func theStaticPiecesRender() async throws {
        let header = HostedViewFixture.host(size: NSSize(width: 320, height: 40)) {
            KeymapSectionHeader(title: "Main Menu \u{25B8} File")
        }
        defer { header.close() }
        let footer = HostedViewFixture.host(size: NSSize(width: 320, height: 40)) {
            KeymapRecordingFooter(hint: "Press the shortcut.")
        }
        defer { footer.close() }
        let note = HostedViewFixture.host(size: NSSize(width: 320, height: 40)) {
            KeymapConflictNote(text: "Also assigned to Save")
        }
        defer { note.close() }

        try await header.settle(.milliseconds(40))
        try await footer.settle(.milliseconds(40))
        try await note.settle(.milliseconds(40))

        #expect(header.renders())
        #expect(footer.renders())
        #expect(note.renders())
    }

    @Test
    func theConflictRowRendersItsMessageAndButtons() async throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let pending = PendingKeymapAssignment(
            command: .save,
            shortcut: .stroke("b", .command),
            mode: .replace,
            conflicts: [.goToDeclaration]
        )
        let hosted = HostedViewFixture.host(size: NSSize(width: 720, height: 60)) {
            KeymapConflictRow(model: session.model, pending: pending)
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(60))

        #expect(hosted.renders())
    }
}
