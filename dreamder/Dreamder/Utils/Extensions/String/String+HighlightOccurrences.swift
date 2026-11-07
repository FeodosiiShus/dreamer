//
//  String+HighlightOccurrences.swift
//  Dreamder
//
//  Created by Raymond Vleeshouwer on 13/06/23.
//

import Foundation
import SwiftUI

extension String {
    /// Highlights occurences of a substring in a string and returns text highlighted as such
    func highlightOccurrences(_ ofSearch: String) -> some View {
        if ofSearch.isEmpty {
            return Text(self)
        }

        let ranges = self.rangesOfSubstring(ofSearch.lowercased())

        var currentIndex = self.startIndex
        var highlightedText = Text("")

        for range in ranges {
            let nonHighlightedText = self[currentIndex..<range.lowerBound]
            let highlightedSubstring = self[range]

            let nonHighlightedLabel = Text(nonHighlightedText).foregroundColor(.secondary)
            let highlightedLabel = Text(highlightedSubstring).foregroundColor(.primary).bold()
            highlightedText = Text("\(highlightedText)\(nonHighlightedLabel)\(highlightedLabel)")

            currentIndex = range.upperBound
        }

        let remainingText = self[currentIndex..<self.endIndex]

        let remainingLabel = Text(remainingText).foregroundColor(.secondary)
        return Text("\(highlightedText)\(remainingLabel)")
    }

    nonisolated private func rangesOfSubstring(_ substring: String) -> [Range<Index>] {
        var ranges = [Range<Index>]()
        var currentIndex = self.startIndex

        while let range = self.range(
            of: substring,
            options: .caseInsensitive,
            range: currentIndex..<self.endIndex
        ) {
            ranges.append(range)

            currentIndex = range.upperBound
        }

        return ranges
    }
}
