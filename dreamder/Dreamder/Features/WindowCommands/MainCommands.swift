//
//  MainCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct MainCommands: Commands {
    var installSceneOpener: SceneOpenerInstall?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            SceneButton(title: "About Dreamder", scene: .about, installSceneOpener: installSceneOpener)
                .keymapShortcut(.about)
        }

        CommandGroup(replacing: .appSettings) {
            SceneButton(title: "Settings...", scene: .settings, installSceneOpener: installSceneOpener)
                .keymapShortcut(.settings)
        }
    }
}

struct SceneButton: View {
    let title: String
    let scene: SceneID
    var open: (@MainActor (SceneID) -> Void)?
    var installSceneOpener: SceneOpenerInstall?

    @Environment(\.openWindow)
    var openWindow

    var body: some View {
        Button(title) {
            if let open {
                open(scene)
            } else {
                openWindow(sceneID: scene)
            }
        }
        .installsSceneOpener(installSceneOpener)
    }
}
