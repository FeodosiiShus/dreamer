import AppKit
import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorPaneClippingTests {
    @Test
    func aDocumentTallerThanItsPaneIsClippedToThePane() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        try await withTempDir { directory in
            let source = (1...600).map { "let value\($0) = \($0)" }.joined(separator: "\n")
            let session = try await DecorationsCoverageHost.open(in: directory, contents: source) { fixture in
                [fixture.document.contentCoordinator, EditorBackgroundCoordinator(defaults: isolated.defaults)]
            }
            defer { session.close() }
            let scrollView = try #require(session.controller.scrollView)
            let gutter = try #require(session.hosted.views(ofType: GutterView.self).first)

            try await eventually { gutter.frame.height > scrollView.frame.height }

            try await eventually { scrollView.clipsToBounds }
        }
    }
}
