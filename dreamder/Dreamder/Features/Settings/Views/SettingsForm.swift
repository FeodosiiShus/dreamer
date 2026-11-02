//
//  SettingsForm.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/8/23.
//

import SwiftUI

struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Islands.island)
        }
        .background(Islands.island)
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
