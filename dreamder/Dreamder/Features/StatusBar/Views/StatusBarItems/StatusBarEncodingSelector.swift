//
//  StatusBarEncodingSelector.swift
//  DreamderModules/StatusBar
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI

struct StatusBarEncodingSelector: View {
    let document: CodeFileDocument?

    var body: some View {
        Text(label)
            .font(Islands.smallFont)
            .foregroundColor(Islands.secondaryForeground)
            .lineLimit(1)
            .fixedSize()
            .help("File encoding")
    }

    private var label: String {
        document?.sourceEncoding?.statusBarLabel ?? FileEncoding.utf8.statusBarLabel
    }
}
