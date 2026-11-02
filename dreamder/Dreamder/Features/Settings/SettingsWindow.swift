//
//  SettingsWindow.swift
//  Dreamder
//
//  Created by Austin Condiff on 3/31/23.
//

import AppKit
import SwiftUI

struct SettingsWindow: Scene {
    var body: some Scene {
        Window("Settings", id: SceneID.settings.rawValue) {
            SettingsView()
                .frame(minWidth: 900, minHeight: 700)
                .task {
                    guard let window = NSApp.windows.first(where: {
                        $0.identifier?.rawValue == SceneID.settings.rawValue
                    }) else {
                        return
                    }
                    configure(window)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
    }

    private func configure(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.tabbingMode = .disallowed
    }
}
