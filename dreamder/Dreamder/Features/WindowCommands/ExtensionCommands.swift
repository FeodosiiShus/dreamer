//
//  ExtensionCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 24/03/2023.
//

import SwiftUI
import CodeEditKit

struct ExtensionCommands: Commands {
    @FocusedValue(ExtensionManager.self) var manager: ExtensionManager?

    @Environment(\.openWindow)
    var openWindow

    var body: some Commands {
        CommandMenu("Extensions") {
            Button("Open Extensions Window") {
                openWindow(sceneID: .extensions)
            }
        }
    }
}
