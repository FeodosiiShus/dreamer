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
        StatusBarWidgetText(text: label)
            .statusBarWidgetFrame()
            .fixedSize()
            .help("File encoding")
    }

    private var label: String {
        document?.sourceEncoding?.statusBarLabel ?? FileEncoding.utf8.statusBarLabel
    }
}
