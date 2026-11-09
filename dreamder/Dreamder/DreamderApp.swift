//
//  DreamderApp.swift
//  Dreamder
//
//  Created by Wouter Hennen on 11/03/2023.
//

import SwiftUI
import AboutWindow

@main
struct DreamderApp: App {
    @NSApplicationDelegateAdaptor var appdelegate: AppDelegate
    let settings = Settings.shared

    init() {
        DreamderHeadless.install()
        ShellEnvironment.shared.prepare()

        _ = DreamderDocumentController.shared
        NSMenuItem.swizzle()
        NSSplitViewItem.swizzle()
    }

    var body: some Scene {
        Group {
            WelcomeScene()
            AboutWindow(
                title: "Dreamder",
                subtitleView: { AboutSubtitleView() },
                actions: {
                    AboutButton(title: "Acknowledgements", destination: {
                        AcknowledgementsView()
                    })
                },
                footer: { AboutFooterView() }
            )

            SettingsWindow()
                .commands {
                    DreamderCommands()
                    RefactorCommands()
                    CodeCommands()
                    ProblemsCommands()
                    InlayHintCommands()
                    StructureCommands()
                    FindInFilesCommands()
                }
        }
        .environment(\.settings, settings.preferences) // Add settings to each window environment
    }
}
