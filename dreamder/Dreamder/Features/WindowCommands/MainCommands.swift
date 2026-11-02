//
//  MainCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct MainCommands: Commands {
    @Environment(\.openWindow)
    var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Dreamder") {
                openWindow(sceneID: .about)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(sceneID: .settings)
            }
            .keyboardShortcut(",")
        }
    }
}
