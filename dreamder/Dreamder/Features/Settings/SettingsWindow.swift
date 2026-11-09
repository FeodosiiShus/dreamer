//
//  SettingsWindow.swift
//  Dreamder
//
//  Created by Austin Condiff on 3/31/23.
//

import AppKit
import SwiftUI

struct SettingsWindowContent: View {
    var body: some View {
        SettingsView()
            .frame(minWidth: 900, minHeight: 700)
            .task {
                SettingsWindow.configureSettingsWindow(in: NSApp.windows)
            }
    }
}

struct SettingsWindow: Scene {
    var body: some Scene {
        Window("Settings", id: SceneID.settings.rawValue) {
            SettingsWindowContent()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
    }

    static func configureSettingsWindow(in windows: [NSWindow]) {
        guard let window = windows.first(where: { $0.isSettingsWindow }) else {
            return
        }
        configure(window)
    }

    static func configure(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.tabbingMode = .disallowed
    }
}
