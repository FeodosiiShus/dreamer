//
//  View+ConstrainHeightToWindow.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/3/23.
//

import SwiftUI
import Combine

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
    func constrainHeightToWindow() -> some View {
        modifier(ConstrainHeightToWindowViewModifier())
    }
}

struct ConstrainHeightToWindowViewModifier: ViewModifier {
    @State var height: CGFloat = 100

    func body(content: Content) -> some View {
        content
            .frame(height: height-100)
            .onReceive(frameChanges) { newValue in
                height = newValue.height
            }
    }

    private var frameChanges: AnyPublisher<NSRect, Never> {
        guard let window = NSApp.settingsWindow else { return Empty().eraseToAnyPublisher() }
        return window.publisher(for: \.frame).eraseToAnyPublisher()
    }
}
