//
//  NSApp+openWindow.swift
//  Dreamder
//
//  Created by Wouter Hennen on 14/03/2023.
//

import AppKit
import SwiftUI

extension OpenWindowAction {
    func callAsFunction(sceneID: SceneID) {
        callAsFunction(id: sceneID.rawValue)
    }
}

extension NSApplication {
    func closeWindow(_ ids: SceneID..., in windows: [NSWindow] = NSApp.windows) {
        ids.forEach { id in
            windows.first { $0.identifier?.rawValue == id.rawValue }?.close()
        }
    }

    var openSwiftUIWindows: Int {
        NSApp
            .windows
            .compactMap(\.identifier?.rawValue)
            .compactMap { SceneID(rawValue: $0) }
            .count
    }
}
