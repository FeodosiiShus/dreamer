//
//  SettingsInjector.swift
//  Dreamder
//
//  Created by Wouter Hennen on 28/04/2023.
//

import SwiftUI

struct SettingsInjector<Content: View>: View {
    @Environment(\.settingsStore)
    private var store

    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.settings, store.preferences)
    }
}
