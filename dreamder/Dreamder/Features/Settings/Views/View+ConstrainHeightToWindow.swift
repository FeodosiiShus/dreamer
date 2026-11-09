//
//  View+ConstrainHeightToWindow.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/3/23.
//

import SwiftUI

extension NSWindow {
    var isSettingsWindow: Bool {
        self.identifier?.rawValue == SceneID.settings.rawValue
    }
}

extension NSApplication {
    var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.isSettingsWindow }
    }
}

extension View {
    func constrainHeightToWindow(
        of window: @escaping @MainActor () -> NSWindow? = { NSApp.settingsWindow }
    ) -> some View {
        modifier(ConstrainHeightToWindowViewModifier(window: window))
    }
}

struct ConstrainHeightToWindowViewModifier: ViewModifier {
    let window: @MainActor () -> NSWindow?

    @State private var windowHeight: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(height: windowHeight.map { $0 - Self.reservedHeight })
            .onAppear { windowHeight = window()?.frame.height }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                guard let resized = notification.object as? NSWindow, resized === window() else { return }
                windowHeight = resized.frame.height
            }
    }

    private static let reservedHeight: CGFloat = 100
}
