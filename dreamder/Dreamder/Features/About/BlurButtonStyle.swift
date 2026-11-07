//
//  BlurButtonStyle.swift
//  Dreamder
//
//  Created by Wouter Hennen on 21/01/2023.
//

import SwiftUI

extension ButtonStyle where Self == BlurButtonStyle {
    static var blur: BlurButtonStyle { BlurButtonStyle() }
    static var secondaryBlur: BlurButtonStyle { BlurButtonStyle(isSecondary: true) }
}

struct BlurButtonStyle: ButtonStyle {
    var isSecondary: Bool = false

    @Environment(\.controlSize)
    var controlSize

    var height: CGFloat {
        switch controlSize {
        case .large:
            return 28
        default:
            return 20
        }
    }

    private var glass: Glass {
        isSecondary ? .regular.interactive() : .regular.tint(Color.gray.opacity(0.30)).interactive()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: height)
            .glassEffect(glass, in: .capsule)
    }
}
