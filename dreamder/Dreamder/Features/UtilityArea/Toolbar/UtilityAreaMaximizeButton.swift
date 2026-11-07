//
//  UtilityAreaMaximizeButton.swift
//  Dreamder
//
//  Created by Stef Kors on 12/04/2022.
//

import SwiftUI

struct UtilityAreaMaximizeButton: View {
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel

    var body: some View {
        Button {
            utilityAreaViewModel.isMaximized.toggle()
        } label: {
            Image(systemName: "arrowtriangle.up.square")
                .foregroundColor(utilityAreaViewModel.isMaximized ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
