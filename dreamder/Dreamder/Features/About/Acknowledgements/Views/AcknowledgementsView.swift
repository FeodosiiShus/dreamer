//
//  AcknowledgementsView.swift
//  DreamderModules/Acknowledgements
//
//  Created by Shivesh M M on 4/4/22.
//

import SwiftUI
import AboutWindow

struct AcknowledgementsView: View {
    @State private var model = AcknowledgementsViewModel()

    var body: some View {
        AboutDetailView(title: "Acknowledgements") { AcknowledgementsListView(model: model) }
    }
}

struct AcknowledgementsListView: View {
    let model: AcknowledgementsViewModel

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(
                model.indexedAcknowledgements,
                id: \.acknowledgement.name
            ) { (index, acknowledgement) in
                if index != 0 {
                    Divider()
                        .frame(height: 0.5)
                        .opacity(0.5)
                }
                AcknowledgementRowView(acknowledgement: acknowledgement)
            }
        }
    }
}
