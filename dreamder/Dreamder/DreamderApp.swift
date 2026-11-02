//
//  DreamderApp.swift
//  Dreamder
//
//  Created by Wouter Hennen on 11/03/2023.
//

import SwiftUI
import WelcomeWindow
import AboutWindow

@main
struct DreamderApp: App {
    @NSApplicationDelegateAdaptor var appdelegate: AppDelegate
    @ObservedObject var settings = Settings.shared

    init() {
        ShellEnvironment.shared.prepare()

        // Register singleton services before anything else
        ServiceContainer.register(
            LSPService()
        )

        _ = DreamderDocumentController.shared
        NSMenuItem.swizzle()
        NSSplitViewItem.swizzle()
    }

    var body: some Scene {
        Group {
            WelcomeWindow(
                title: "Dreamder",
                subtitleView: { WelcomeSubtitleView() },
                actions: { dismissWindow in
                    NewFileButton(dismissWindow: dismissWindow)
                    GitCloneButton(dismissWindow: dismissWindow)
                    OpenFileOrFolderButton(dismissWindow: dismissWindow)
                },
                onDrop: { url, dismissWindow in
                    Task {
                        await DreamderDocumentController.shared.openDocument(at: url, onCompletion: { dismissWindow() })
                    }
                }
            )

            ExtensionManagerWindow()

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
                }
        }
        .environment(\.settings, settings.preferences) // Add settings to each window environment
    }
}
