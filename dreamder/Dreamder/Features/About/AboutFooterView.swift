//
//  AboutFooterView.swift
//  Dreamder
//
//  Created by Giorgi Tchelidze on 08.06.25.
//

import SwiftUI
import AboutWindow

struct AboutFooterView: View {
    static func copyrightText(_ copyright: String?) -> String {
        copyright ?? ""
    }

    var body: some View {
        FooterView(
            primaryView: {
                Text("MIT License")
            },
            secondaryView: {
                Text(Self.copyrightText(Bundle.copyrightString))
            }
        )
    }
}
