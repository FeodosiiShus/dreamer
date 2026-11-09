//
//  DreamderCommands.swift
//  Dreamder
//
//  Created by Wouter Hennen on 11/03/2023.
//

import SwiftUI

struct DreamderCommands: Commands {
    @AppSettings(\.sourceControl.general.sourceControlIsEnabled)
    private var sourceControlIsEnabled
    private let installSceneOpener: SceneOpenerInstall?

    init(installSceneOpener: SceneOpenerInstall? = nil) {
        self.installSceneOpener = installSceneOpener
    }

    var body: some Commands {
        Group { // SwiftUI limits to 9 items in an initializer, so we have to group every 9 items.
            MainCommands(installSceneOpener: installSceneOpener)
            FileCommands()
            Group {
                ViewCommands()
                MarkdownCommands()
            }
            FindCommands()
            NavigateCommands()
            TasksCommands()
            if sourceControlIsEnabled { SourceControlCommands() }
            EditorCommands()
            WindowCommands()
        }
        AppearanceCommands()
    }
}
