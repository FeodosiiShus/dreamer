//
//  IconToggleStyle.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/9/23.
//

import SwiftUI

struct IconToggleStyle: ToggleStyle {
    var font: Font?
    var size: CGSize?

    init(font: Font? = nil, size: CGSize? = nil) {
        self.font = font
        self.size = size
    }

    func makeBody(configuration: ToggleStyle.Configuration) -> some View {
        Button(action: Self.toggler(configuration.$isOn)) { configuration.label }
            .buttonStyle(.icon(isActive: configuration.isOn, font: font, size: size))
    }

    static func toggler(_ isOn: Binding<Bool>) -> () -> Void {
        { isOn.wrappedValue.toggle() }
    }
}

extension ToggleStyle where Self == IconToggleStyle {
    static func icon(
        font: Font? = Font.system(size: 14.5, weight: .regular, design: .default),
        size: CGSize? = CGSize(width: 24, height: 24)
    ) -> IconToggleStyle {
        return IconToggleStyle(font: font, size: size)
    }
    static var icon: IconToggleStyle { .init() }
}
