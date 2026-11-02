//
//  NewFileButton.swift
//  Dreamder
//
//  Created by Giorgi Tchelidze on 07.06.25.
//

import SwiftUI
import WelcomeWindow

struct NewFileButton: View {

    var dismissWindow: () -> Void

    var body: some View {
        WelcomeButton(
            iconName: "plus.square",
            title: "Create New File...",
            action: {
                let documentController = DreamderDocumentController()
                documentController.createAndOpenNewDocument(onCompletion: { dismissWindow() })
            }
        )
    }
}
