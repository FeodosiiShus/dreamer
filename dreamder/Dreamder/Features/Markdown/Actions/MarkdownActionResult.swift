import Foundation

nonisolated struct MarkdownTextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
}

nonisolated struct MarkdownActionResult: Equatable, Sendable {
    let text: String
    let selections: [NSRange]
    let edits: [MarkdownTextEdit]

    init(original: [UInt16], updated: [UInt16], selections: [NSRange]) {
        self.text = String(decoding: updated, as: UTF16.self)
        self.selections = selections
        if let edit = Self.minimalEdit(from: original, to: updated) {
            self.edits = [edit]
        } else {
            self.edits = []
        }
    }

    static func minimalEdit(from original: [UInt16], to updated: [UInt16]) -> MarkdownTextEdit? {
        guard original != updated else { return nil }
        let limit = min(original.count, updated.count)
        var prefix = 0
        while prefix < limit, original[prefix] == updated[prefix] {
            prefix += 1
        }
        if prefix > 0, UTF16.isLeadSurrogate(original[prefix - 1]) {
            prefix -= 1
        }
        var suffix = 0
        while suffix < limit - prefix, original[original.count - 1 - suffix] == updated[updated.count - 1 - suffix] {
            suffix += 1
        }
        if suffix > 0, UTF16.isTrailSurrogate(original[original.count - suffix]) {
            suffix -= 1
        }
        let removed = prefix..<(original.count - suffix)
        let inserted = prefix..<(updated.count - suffix)
        return MarkdownTextEdit(
            range: NSRange(location: removed.lowerBound, length: removed.count),
            replacement: String(decoding: updated[inserted], as: UTF16.self)
        )
    }

    func applied(to original: String) -> String {
        let units = Array(original.utf16)
        var result = units
        for edit in edits {
            let range = edit.range.location..<(edit.range.location + edit.range.length)
            result.replaceSubrange(range, with: Array(edit.replacement.utf16))
        }
        return String(decoding: result, as: UTF16.self)
    }
}

nonisolated struct MarkdownEditBuffer: Sendable {
    private(set) var units: [UInt16]
    private let original: [UInt16]
    private(set) var settled: [NSRange] = []

    init(_ string: String) {
        let units = Array(string.utf16)
        self.units = units
        self.original = units
    }

    init(units: [UInt16]) {
        self.units = units
        self.original = units
    }

    var length: Int { units.count }

    mutating func replace(_ range: Range<Int>, with replacement: [UInt16]) {
        let delta = replacement.count - range.count
        units.replaceSubrange(range, with: replacement)
        settled = settled.map { selection in
            let start = Self.shifted(
                selection.location,
                replacing: range,
                replacementLength: replacement.count,
                delta: delta
            )
            let end = Self.shifted(
                selection.location + selection.length,
                replacing: range,
                replacementLength: replacement.count,
                delta: delta
            )
            return NSRange(location: start, length: max(end - start, 0))
        }
    }

    mutating func replace(_ range: Range<Int>, with replacement: String) {
        replace(range, with: Array(replacement.utf16))
    }

    mutating func insert(_ text: String, at offset: Int) {
        replace(offset..<offset, with: Array(text.utf16))
    }

    mutating func delete(_ range: Range<Int>) {
        replace(range, with: [])
    }

    mutating func settle(_ selection: NSRange) {
        settled.append(selection)
    }

    mutating func settleFirst(_ selection: NSRange) {
        settled.insert(selection, at: 0)
    }

    func result(selections: [NSRange]) -> MarkdownActionResult {
        MarkdownActionResult(original: original, updated: units, selections: selections)
    }

    func resultWithSettledSelections() -> MarkdownActionResult {
        result(selections: settled)
    }

    private static func shifted(
        _ position: Int,
        replacing range: Range<Int>,
        replacementLength: Int,
        delta: Int
    ) -> Int {
        if position >= range.upperBound {
            return position + delta
        }
        if position > range.lowerBound {
            return range.lowerBound + replacementLength
        }
        return position
    }
}
