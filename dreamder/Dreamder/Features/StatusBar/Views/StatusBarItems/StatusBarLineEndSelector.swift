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
        Text(label)
            .font(Islands.smallFont)
            .foregroundColor(Islands.secondaryForeground)
            .lineLimit(1)
            .fixedSize()
            .help("Line separator")
    }

    private var label: String {
        guard let content = document?.content?.string else { return "LF" }
        return content.contains("\r\n") ? "CRLF" : "LF"
    }
}
