//
//  CECircularProgressView.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 21.06.24.
//

import SwiftUI

struct CECircularProgressView: View {
    @State private var isAnimating = false
    @State private var previousValue: Bool = false

    let lineWidth: CGFloat = 2

    var body: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: lineWidth))
            .foregroundStyle(.tertiary)
            .overlay {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(
                        previousValue ?
                            .degrees(isAnimating ?  0 : -360)
                        : .degrees(isAnimating ? 360 : 0)
                    )
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear {
                        self.previousValue = isAnimating
                        self.isAnimating.toggle()
                    }
            }
            .rotationEffect(.degrees(-90))
            .padding(lineWidth/2)
            .accessibilityElement()
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityValue(Text("working"))
    }
}
