//
//  AcknowledgementsRowView.swift
//  Dreamder
//
//  Created by Austin Condiff on 1/19/23.
//

import SwiftUI

struct AcknowledgementRowView: View {
    let acknowledgement: AcknowledgementDependency

    var body: some View {
        HStack {
            Text(acknowledgement.name)
                .font(.body)

            Spacer()

            Link(destination: acknowledgement.repositoryURL) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
