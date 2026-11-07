//
//  String+Normalise.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 03.02.24.
//

import Foundation

nonisolated extension String {
    /// Normalises the characters of the string by converting them to ASCII representation.
    /// Each character is transformed into its ASCII equivalent, and the resulting array
    /// of FuzzySearchCharacter objects contains both the original and normalised content.
    ///
    /// - Returns: An array of FuzzySearchCharacter objects representing the original and
    /// normalised content of each character in the string.
    func normalise() -> [FuzzySearchCharacter] {
        return self.lowercased().map { char in
            let content = String(char)
            return FuzzySearchCharacter(
                content: content,
                normalisedContent: content.folding(options: .diacriticInsensitive, locale: nil)
            )
        }
    }
}
