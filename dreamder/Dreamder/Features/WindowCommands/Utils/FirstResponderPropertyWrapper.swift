//
//  FirstResponderPropertyWrapper.swift
//  Dreamder
//
//  Created by Wouter Hennen on 14/03/2023.
//

import SwiftUI
import Combine

/// A property wrapper which allows for easy access to the current first responder.
/// This differs from the SwiftUI Focus System, as you get AppKit NSResponders, which you can call methods on.
/// It can also be easily checked if the current first selector accepts some event.
@propertyWrapper
struct FirstResponder: DynamicProperty {
    @State var helper = HelperClass()

    var wrappedValue: NSResponder? {
        helper.responder
    }

    @Observable
    final class HelperClass {
        var responder: NSResponder? = NSApp.keyWindow?.firstResponder

        @ObservationIgnored private var responderCancellable: AnyCancellable?

        init() {
            responderCancellable = NSApp.publisher(for: \.keyWindow?.firstResponder).sink { [weak self] responder in
                self?.responder = responder
            }
        }
    }
}
