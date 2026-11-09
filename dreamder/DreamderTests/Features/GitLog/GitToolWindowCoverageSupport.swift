import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
struct GitToolWindowCovInput {
    let hosted: HostedView

    init(hosted: HostedView) {
        self.hosted = hosted
        let size = hosted.hosting.bounds.size
        hosted.window.styleMask = [.borderless]
        hosted.window.setContentSize(size)
        hosted.layout()
    }

    private func windowLocation(_ point: CGPoint) -> NSPoint {
        let hosting = hosted.hosting
        let local = hosting.isFlipped
            ? NSPoint(x: point.x, y: point.y)
            : NSPoint(x: point.x, y: hosting.bounds.height - point.y)
        return hosting.convert(local, to: nil)
    }

    private func rightMouseDown(at point: CGPoint) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: windowLocation(point),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: hosted.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    func contextMenu(at point: CGPoint) throws -> NSMenu {
        try #require(hosted.hosting.menu(for: try rightMouseDown(at: point)))
    }
}

nonisolated struct GitToolWindowCovRepo: Sendable {
    static let longBody = (1...12)
        .map { "Paragraph \($0) explains why this change exists and keeps going well past a single line so the details pane has to wrap it." }
        .joined(separator: "\n\n")

    let fixture: GitMergeFixture

    static func make(in directory: URL) async throws -> GitToolWindowCovRepo {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a-\(UUID().uuidString)\n")
        try fixture.write("docs/guide.md", "guide\n")
        try await fixture.commit("initial")
        try await fixture.run("tag", "v1")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/feature.txt", "feature\n")
        try fixture.write("src/nested/deep.txt", "deep\n")
        try await fixture.run("add", "-A")
        try await fixture.run("commit", "-q", "-m", "Feature work", "-m", longBody)
        try await fixture.run("commit", "-q", "--allow-empty", "-m", "Empty marker")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("a.txt", "main\n")
        try await fixture.commit("Main change")
        try await fixture.run("merge", "-q", "--no-ff", "feature", "-m", "Merge feature")
        try await fixture.run("rm", "-q", "docs/guide.md")
        try await fixture.run("commit", "-q", "-m", "Remove guide")
        return GitToolWindowCovRepo(fixture: fixture)
    }
}
