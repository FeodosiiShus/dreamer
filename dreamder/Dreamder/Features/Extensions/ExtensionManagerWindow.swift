//
//  ExtensionManagerWindow.swift
//  Dreamder
//
//  Created by Wouter Hennen on 24/03/2023.
//

import SwiftUI

struct ExtensionManagerWindow: Scene {
    let manager = ExtensionManager.shared

    @State var selection = Set<ExtensionInfo>()

    var body: some Scene {
        Window("Extensions", id: SceneID.extensions.rawValue) {
            NavigationSplitView {
                ExtensionsListView(selection: $selection)
            } detail: {
                switch selection.count {
                case 0:
                    Text("Select an extension")
                case 1:
                    if let ext = selection.first {
                        ExtensionDetailView(ext: ext)
                    }
                default:
                    Text("\(selection.count) selected")
                }
            }
            .environment(manager)
            .focusedValue(manager)
        }
    }
}
