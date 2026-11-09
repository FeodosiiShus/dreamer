import AppKit
import SwiftUI
import Testing
@testable import Dreamder

extension FindNavigatorFormTests {
    @Test
    func submitSearchRunsTheSearchOrClearsResults() async throws {
        try await withState(files: ["a.txt": "foo foo\nbar\n"]) { _, state, _ in
            let form = FindNavigatorForm(state: state)
            state.searchQuery = "foo"
            form.submitSearch()
            try await eventually { state.searchResult.count == 1 }

            state.searchQuery = ""
            form.submitSearch()
            try await eventually { state.searchResult.isEmpty && state.searchResultsCount == 0 }

            state.searchResultsCount = 5
            form.clearSearch()
            try await eventually { state.searchResultsCount == 0 }
        }
    }

    @Test
    func replaceAllRewritesTheMatchingFilesOnDisk() async throws {
        try await withState(files: ["a.txt": "foo foo\n"]) { _, state, dir in
            let form = FindNavigatorForm(state: state)
            state.selectedMode = [.Replace, .Text, .Containing]
            state.searchQuery = "foo"
            state.replaceText = "bar"
            form.replaceAll()
            try await eventually { state.findNavigatorStatus == .replaced(updatedFiles: 1) }
            #expect(try String(contentsOf: dir.appending(path: "a.txt"), encoding: .utf8) == "bar bar\n")
        }
    }

    @Test
    func optionTogglesFlipTheBoundModelFlags() async throws {
        try await withState { workspace, state, _ in
            FindOptionToggle(glyph: .text("Cc"), isOn: Bindable(state).caseSensitive, help: "Match Case").toggle()
            #expect(state.caseSensitive)
            FindOptionToggle(glyph: .text("Cc"), isOn: Bindable(state).caseSensitive, help: "Match Case").toggle()
            #expect(state.caseSensitive == false)

            FindOptionToggle(glyph: .text(".*"), isOn: Bindable(state).isRegularExpression, help: "Regex").toggle()
            #expect(state.selectedMode == [.Find, .RegularExpression])

            let enabled = try HostedViewFixture.hostInWorkspace(workspace) {
                HStack {
                    FindOptionToggle(glyph: .symbol("folder"), isOn: Bindable(state).caseSensitive, help: "on")
                    FindOptionToggle(glyph: .text("W"), isOn: Bindable(state).wholeWordsOnly, help: "off")
                        .disabled(true)
                }
            }
            defer { enabled.close() }
            try await enabled.settle()
            let caseOn = enabled.snapshot()
            state.caseSensitive = true
            try await enabled.settle()
            #expect(HostedView.pixelsDiffer(caseOn, enabled.snapshot()))
        }
    }

    @Test
    func multilineFieldSubmitsOnReturnUnlessShiftIsHeld() async throws {
        try await withState { _, state, _ in
            let plain = FindFormSubmitCounter()
            let plainHost = HostedViewFixture.host {
                FindFormMultilineHarness(state: state, counter: plain, modifiers: [])
            }
            defer { plainHost.close() }
            try await plainHost.settle()
            let field = try #require(plain.field)
            #expect(field.submitOnReturn() == .handled)
            #expect(plain.submissions == 1)

            let shifted = FindFormSubmitCounter()
            let shiftHost = HostedViewFixture.host {
                FindFormMultilineHarness(state: state, counter: shifted, modifiers: .shift)
            }
            defer { shiftHost.close() }
            try await shiftHost.settle()
            let shiftField = try #require(shifted.field)
            #expect(shiftField.submitOnReturn() == .ignored)
            #expect(shifted.submissions == 0)

            _ = FindMultilineField.activeModifiers()
        }
    }

    @Test
    func multilineFieldReadsTheApplicationModifiersByDefault() async throws {
        try await withState { _, state, _ in
            let counter = FindFormSubmitCounter()
            let hosted = HostedViewFixture.host {
                FindFormDefaultModifiersHarness(state: state, counter: counter)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let field = try #require(counter.field)

            #expect(field.currentModifiers() == FindMultilineField.activeModifiers())
        }
    }

    @Test
    func multilineFieldShowsAndClearsTheQuery() async throws {
        try await withState { _, state, _ in
            state.searchQuery = "one\ntwo"
            let counter = FindFormSubmitCounter()
            let hosted = HostedViewFixture.host {
                FindFormMultilineHarness(state: state, counter: counter, modifiers: [])
            }
            defer { hosted.close() }
            try await hosted.settle()
            let filled = hosted.snapshot()
            #expect(hosted.renders())

            let field = try #require(counter.field)
            field.clear()
            try await eventually { state.searchQuery.isEmpty }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(filled, hosted.snapshot()))
        }
    }

    @Test
    func formRendersMultilineQueryRowWhenMultilineIsOn() async throws {
        try await withState { workspace, state, _ in
            state.findModel.isMultiline = true
            state.searchQuery = "a\nb"
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let multiline = hosted.snapshot()

            state.findModel.isMultiline = false
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(multiline, hosted.snapshot()))
        }
    }

    @Test
    func activeModifiersFollowTheGivenEventAndAreEmptyWithoutOne() throws {
        #expect(FindMultilineField.activeModifiers(event: nil) == [])

        let shiftPressed = try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        ))
        #expect(FindMultilineField.activeModifiers(event: shiftPressed).contains(.shift))
    }

    @Test
    func multilineFieldBorderIsAccentedOnlyWhileFocused() {
        #expect(FindMultilineField.borderColor(isFocused: true) == Islands.accent)
        #expect(FindMultilineField.borderColor(isFocused: false) == Islands.popupBorder)
        #expect(Islands.accent != Islands.popupBorder)
    }

    @Test
    func formWithoutASecondModeShowsTheDefaultFindPlaceholder() async throws {
        try await withState { workspace, state, _ in
            state.selectedMode = [.Find]
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(hosted.views(of: NSPopUpButton.self).count == 1)
            let single = hosted.snapshot()

            state.selectedMode = [.Find, .Text, .Containing]
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(single, hosted.snapshot()))
        }
    }
}
