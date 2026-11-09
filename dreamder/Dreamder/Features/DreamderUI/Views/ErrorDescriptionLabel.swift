//
//  ErrorDescriptionLabel.swift
//  Dreamder
//
//  Created by Khan Winter on 8/14/25.
//

import SwiftUI

struct ErrorDescriptionLabel: View {
    let error: Error

    nonisolated static func lines(for error: Error) -> [String] {
        guard let error = error as? LocalizedError else {
            return [error.localizedDescription]
        }
        return [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(Self.lines(for: error).enumerated()), id: \.offset) { _, line in
                Text(line)
            }
        }
    }
}
