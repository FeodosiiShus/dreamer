//
//  WindowControllerPropertyWrapper.swift
//  Dreamder
//
//  Created by Khan Winter on 7/14/24.
//

import AppKit
import SwiftUI
import Combine

/// Provides an auto-updating reference to ``DreamderWindowController``. The value will update as the key window
/// changes, and does not keep a strong reference to the controller.
///
/// Sample usage:
/// ```swift
/// struct WindowCommands: Commands {
///     @UpdatingWindowController var windowController
///
///     var body: some Commands {
///         Button("Button that needs the window") {
///             print("Window exists")
///         }
///         .disabled(windowController == nil)
///     }
/// }
/// ```
@propertyWrapper
struct UpdatingWindowController: DynamicProperty {
    @State var box = WindowControllerBox()

    var wrappedValue: DreamderWindowController? {
        box.controller
    }

    @Observable
    final class WindowControllerBox {
        @ObservationIgnored private weak var weakController: DreamderWindowController?
        // Needs to stick around between window changes.
        @ObservationIgnored private var windowCancellable: AnyCancellable?

        var controller: DreamderWindowController? {
            get {
                access(keyPath: \.controller)
                return weakController
            }
            set {
                withMutation(keyPath: \.controller) {
                    weakController = newValue
                }
            }
        }

        init() {
            windowCancellable = NSApp.publisher(for: \.keyWindow).receive(on: RunLoop.main).sink { [weak self] window in
                // Fix an issue where NSMenuItems with custom views would trigger this callback.
                guard window?.className != "NSPopupMenuWindow" else { return }
                self?.controller = window?.windowController as? DreamderWindowController
            }
        }
    }
}
