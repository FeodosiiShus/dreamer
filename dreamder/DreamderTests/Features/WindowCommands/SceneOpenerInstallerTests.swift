import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SceneOpenerInstallerTests {
    @MainActor
    private final class InstallRecorder {
        private(set) var openers: [@MainActor (SceneID) -> Void] = []

        func record(_ opener: @escaping @MainActor (SceneID) -> Void) {
            openers.append(opener)
        }
    }

    @Test
    func theModifierHandsTheEnvironmentOpenerToTheInstallerWhenTheViewAppears() async throws {
        let recorder = InstallRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 100, height: 100)) {
            Color.clear.installsSceneOpener { recorder.record($0) }
        }
        defer { hosted.close() }

        try await eventually { !recorder.openers.isEmpty }

        let opener = try #require(recorder.openers.first)
        opener(.about)
    }

    @Test
    func theDelegateInstallerReceivesTheOpenerFromTheHostedView() async throws {
        let delegate = AppDelegate()
        let hosted = HostedViewFixture.host(size: NSSize(width: 100, height: 100)) {
            Color.clear.installsSceneOpener { delegate.installSceneOpener($0) }
        }
        defer { hosted.close() }

        try await eventually { delegate.sceneOpener != nil }

        #expect(delegate.sceneOpener != nil)
    }
}
