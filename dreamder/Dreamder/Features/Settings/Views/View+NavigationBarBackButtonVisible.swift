//
//  View+NavigationBarBackButtonVisible.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/8/23.
//

import SwiftUI

struct NavigationBarBackButton: View {
    @Environment(\.presentationMode)
    var presentationMode

    var body: some View {
        Button(action: dismiss) {
            Image(systemName: "chevron.left")
                .frame(width: 23)
        }
    }

    func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}

struct NavigationBarBackToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { NavigationBarBackButton() }
    }
}

struct NavigationBarBackButtonVisible: ViewModifier {
    @Environment(SettingsViewModel.self) private var model

    func body(content: Content) -> some View {
        content
        .toolbar { NavigationBarBackToolbar() }
        .navigationBarBackButtonHidden()
        .onAppear {
            model.backButtonVisible = true
        }
        .onDisappear {
            model.backButtonVisible = false
        }
    }
}

extension View {
    func navigationBarBackButtonVisible() -> some View {
        modifier(NavigationBarBackButtonVisible())
    }
}
