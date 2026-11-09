//
//  StatusBarLineEndSelector.swift
//  DreamderModules/StatusBar
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI

struct StatusBarLineEndSelector: View {
    let document: CodeFileDocument?

    var body: some View {
        StatusBarWidgetText(text: label)
            .statusBarWidgetFrame()
            .fixedSize()
            .help("Line separator")
    }

    private var label: String {
        guard let content = document?.content?.string else { return "LF" }
        return content.contains("\r\n") ? "CRLF" : "LF"
    }
}
