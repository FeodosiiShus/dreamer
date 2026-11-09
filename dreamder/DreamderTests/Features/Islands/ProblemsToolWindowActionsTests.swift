import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProblemsToolWindowActionsTests {
    private func diagnostic(_ url: URL) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: 1,
            startColumn: 2,
            endLine: 1,
            endColumn: 3,
            severity: .error,
            message: "boom",
            source: nil,
            code: nil
        )
    }

    @Test
    func selectingATabSwitchesTheModelTab() {
        let model = ProblemsToolWindowModel()

        model.select(.project)
        #expect(model.tab == .project)

        model.select(.file)
        #expect(model.tab == .file)
    }

    @Test
    func boundSeverityToggleHidesAndShowsTheGroup() {
        let model = ProblemsToolWindowModel()
        let toggle = bound(model.toggleSeverity, ProblemSeverityGroup.errors)

        toggle()
        #expect(!model.severityFilter.isShown(.errors))

        toggle()
        #expect(model.severityFilter.isShown(.errors))
    }

    @Test
    func activationWithoutASelectionHandlesTheKeyPress() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let model = ProblemsToolWindowModel()

            #expect(model.activation(workspace: workspace)() == .handled)
        }
    }

    @Test
    func openingActionSelectsTheDiagnosticAndNavigatesToIt() async throws {
        try await withTempDir { directory in
            let file = directory.appending(path: "First.swift")
            try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let model = ProblemsToolWindowModel()
            let problem = diagnostic(file)

            model.opening(problem, fileURL: file, workspace: workspace)()

            #expect(model.selection == .diagnostic(problem))
            let manager = try #require(workspace.editorManager)
            try await eventually {
                manager.activeEditor.selectedTab?.file.url.standardizedFileURL == file.standardizedFileURL
            }
        }
    }

    @Test
    func severityToggleHoverStateIsSettable() {
        let toggle = ProblemSeverityToggle(group: .errors, isOn: true, action: {})

        toggle.setHovering(true)
        toggle.setHovering(false)
    }

    @Test
    func severityToggleBackgroundPrefersHoverThenSelection() {
        #expect(ProblemSeverityToggle.background(isHovering: true, isOn: false) == Islands.actionHover)
        #expect(ProblemSeverityToggle.background(isHovering: true, isOn: true) == Islands.actionHover)
        #expect(ProblemSeverityToggle.background(isHovering: false, isOn: true) == Islands.selection)
        #expect(ProblemSeverityToggle.background(isHovering: false, isOn: false) == .clear)
    }
}
