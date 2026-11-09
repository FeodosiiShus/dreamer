//
//  FontWeightPicker.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/13/24.
//

import SwiftUI

struct FontWeightPicker: View {
    @Binding var selection: NSFont.Weight
    var label: String?

    static let options: [(weight: NSFont.Weight, name: String)] = [
        (.ultraLight, "Ultra Light"),
        (.thin, "Thin"),
        (.light, "Light"),
        (.regular, "Regular"),
        (.medium, "Medium"),
        (.semibold, "Semi Bold"),
        (.bold, "Bold"),
        (.heavy, "Heavy"),
        (.black, "Black")
    ]

    var body: some View {
        Picker(label ?? "Font Weight", selection: $selection) {
            ForEach(Self.options, id: \.weight) { option in
                Text(option.name)
                    .tag(option.weight)
            }
        }
    }
}
