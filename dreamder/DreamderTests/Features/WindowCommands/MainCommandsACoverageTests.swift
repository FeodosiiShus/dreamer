import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MainCommandsACoverageTests {
    @MainActor
    private final class SceneRecorder {
        private(set) var scenes: [SceneID] = []

        func record(_ scene: SceneID) {
            scenes.append(scene)
        }
    }

    @Test
    func sceneButtonOpensItsSceneThroughTheInjectedOpener() throws {
        let recorder = SceneRecorder()
        let menu = CommandsACoverageSupport.host {
            SceneButton(title: "About Dreamder", scene: .about, open: { recorder.record($0) })
            SceneButton(title: "Settings...", scene: .settings, open: { recorder.record($0) })
            SceneButton(title: "Welcome to Dreamder", scene: .welcome, open: { recorder.record($0) })
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)
        try menu.click(2)

        #expect(recorder.scenes == [.about, .settings, .welcome])
    }

    @Test
    func sceneButtonWithoutAnOpenerUsesTheEnvironmentOpenWindowAction() throws {
        let menu = CommandsACoverageSupport.host {
            SceneButton(title: "About Dreamder", scene: .about)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(menu.titles == ["About Dreamder"])
        #expect(menu.enabledStates == [true])
    }

    @Test
    func commandBodiesBuild() {
        _ = MainCommands().body
        _ = WindowCommands().body
    }
}
