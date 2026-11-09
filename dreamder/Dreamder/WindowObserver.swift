//
//  WindowObserver.swift
//  Dreamder
//
//  Created by Wouter Hennen on 14/01/2023.
//

import SwiftUI

struct WindowObserver<Content: View>: View {

    var window: WindowBox

    @ViewBuilder var content: Content

    /// The fullscreen state of the NSWindow.
    /// This will be passed into all child views as an environment variable.
    @State private var isFullscreen = false

    @State private var modifierKeys = ModifierKeysModel()

    var body: some View {
        content
            .environment(\.modifierKeys, modifierKeys.flags.intersection(.deviceIndependentFlagsMask))
            .onAppear(perform: modifierKeys.start)
            .onDisappear(perform: modifierKeys.stop)
            .environment(\.window, window)
            .environment(\.isFullscreen, isFullscreen)
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification, object: window.value)
            ) { _ in
                self.isFullscreen = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification, object: window.value)
            ) { _ in
                self.isFullscreen = false
            }
    }
}
