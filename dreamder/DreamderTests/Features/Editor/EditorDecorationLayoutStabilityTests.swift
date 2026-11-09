import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorDecorationLayoutStabilityTests {
    private func decorationViews(in hosted: HostedSourceEditor) -> [NSView] {
        let indentGuides: [NSView] = hosted.views(ofType: IndentGuideOverlayView.self)
        let gutterMarkers: [NSView] = hosted.views(ofType: GitGutterMarkerView.self)
        let blameColumns: [NSView] = hosted.views(ofType: GitBlameAnnotationView.self)
        let blameInline: [NSView] = hosted.views(ofType: GitBlameInlineView.self)
        return indentGuides + gutterMarkers + blameColumns + blameInline
    }

    @Test
    func editorWithEveryDecorationStaysStableWhileShrinking() async throws {
        try await withTempDir { directory in
            let start = Date()
            let fixture = try HostedSourceEditorFixture.makeWide(in: directory)
            let hosted = fixture.host()
            defer { hosted.close() }
            var steps: [(date: Date, name: String)] = []
            try await Task.sleep(for: .milliseconds(1_500))
            for width in [1100.0, 800.0, 500.0] {
                steps.append((Date(), "resize to \(width)"))
                hosted.window.setContentSize(NSSize(width: width, height: 700))
                try await Task.sleep(for: .milliseconds(1_500))
            }
            let diagnostics = try await AppKitLayoutLoopDetector.diagnostics(since: start)
            #expect(diagnostics.isEmpty, "\(AppKitLayoutLoopDetector.describe(diagnostics, steps: steps))")
        }
    }

    @Test
    func decorationViewsStayOutsideAutoLayout() async throws {
        try await withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.makeWide(in: directory)
            let hosted = fixture.host()
            defer { hosted.close() }
            try await eventually {
                let views = decorationViews(in: hosted)
                return views.contains { $0 is IndentGuideOverlayView }
                    && views.contains { $0 is GitGutterMarkerView }
                    && views.contains { $0 is GitBlameAnnotationView }
            }
            let decorations = decorationViews(in: hosted)
            #expect(decorations.contains { $0 is IndentGuideOverlayView })
            #expect(decorations.contains { $0 is GitGutterMarkerView })
            #expect(decorations.contains { $0 is GitBlameAnnotationView })
            for view in decorations {
                #expect(view.translatesAutoresizingMaskIntoConstraints == false, "\(type(of: view))")
                #expect(view.autoresizingMask.isEmpty, "\(type(of: view))")
                #expect(view.constraints.isEmpty, "\(type(of: view))")
            }
        }
    }
}
