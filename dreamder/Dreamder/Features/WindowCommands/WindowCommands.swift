//
//  WindowCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct WindowCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .singleWindowList) {
            SceneButton(title: "Welcome to Dreamder", scene: .welcome)
                .keymapShortcut(.windowWelcome)

            SceneButton(title: "About Dreamder", scene: .about)
                .keymapShortcut(.windowAbout)
        }
    }
}
