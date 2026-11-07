//
//  DreamderDividerStyle.swift
//  Dreamder
//
//  Created by Khan Winter on 5/30/25.
//

import AppKit
import SwiftUI

enum DreamderDividerStyle: Equatable {
    enum Thickness: Equatable {
        case thin
        case thick
        case paneSplitter

        var points: CGFloat {
            switch self {
            case .thin: 1
            case .thick: 6
            case .paneSplitter: 10
            }
        }
    }

    case system(Thickness)
    case editorDivider

    var thickness: CGFloat {
        switch self {
        case .system(let thickness):
            return thickness.points
        case .editorDivider:
            return 3.0
        }
    }

    var color: Color {
        switch self {
        case .system:
            return Color(nsColor: .separatorColor)
        case .editorDivider:
            return Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua {
                    NSColor.black
                } else {
                    NSColor(white: 203.0 / 255.0, alpha: 1.0)
                }
            })
        }
    }
}
