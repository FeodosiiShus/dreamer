//
//  GlassEffectView.swift
//  Dreamder
//
//  Created by Khan Winter on 9/2/25.
//

import SwiftUI
import AppKit

struct GlassEffectView: NSViewRepresentable {
    var tintColor: NSColor?

    init(tintColor: NSColor? = nil) {
        self.tintColor = tintColor
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSGlassEffectView()
        view.cornerRadius = 0
        view.tintColor = tintColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? NSGlassEffectView {
            view.tintColor = tintColor
        }
    }
}
