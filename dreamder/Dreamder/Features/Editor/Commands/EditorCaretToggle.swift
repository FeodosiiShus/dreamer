import Foundation

nonisolated enum EditorCaretToggle {
    static func toggled(_ selections: [NSRange], at offset: Int) -> [NSRange] {
        let strictlyInsideSelection = selections.contains {
            $0.length > 0 && $0.location < offset && offset < $0.location + $0.length
        }
        guard !strictlyInsideSelection else { return selections }
        guard let existing = selections.firstIndex(where: { $0.length == 0 && $0.location == offset }) else {
            return selections + [NSRange(location: offset, length: 0)]
        }
        guard selections.count > 1 else { return selections }
        var remaining = selections
        remaining.remove(at: existing)
        return remaining
    }
}
