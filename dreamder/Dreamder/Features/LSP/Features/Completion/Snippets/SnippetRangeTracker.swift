import Foundation

nonisolated struct SnippetRangeTracker: Sendable, Equatable {
    nonisolated struct Slot: Sendable, Equatable {
        var range: NSRange
        var isAlive = true
        let order: Int
    }

    nonisolated struct Stop: Sendable, Equatable {
        let index: Int
        var slots: [Slot]
        let choices: [String]

        var isAlive: Bool {
            slots.contains(where: \.isAlive)
        }

        var isFinal: Bool {
            index == 0
        }
    }

    private(set) var stops: [Stop]

    init(template: SnippetTemplate, origin: Int) {
        var drafts: [(stop: Int, slot: Int, range: NSRange)] = []
        var built: [(index: Int, ranges: [NSRange], choices: [String])] = template.tabStops.map {
            (index: $0.index, ranges: $0.ranges.map { NSRange(location: origin + $0.location, length: $0.length) },
             choices: $0.choices)
        }
        built.append((index: 0, ranges: [NSRange(location: origin + template.finalCaret, length: 0)], choices: []))
        for (stopPosition, stop) in built.enumerated() {
            for (slotPosition, range) in stop.ranges.enumerated() {
                drafts.append((stop: stopPosition, slot: slotPosition, range: range))
            }
        }
        drafts.sort {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            return $0.stop < $1.stop
        }
        var orderedSlots = built.map { stop in stop.ranges.map { Slot(range: $0, order: 0) } }
        for (order, draft) in drafts.enumerated() {
            orderedSlots[draft.stop][draft.slot] = Slot(range: draft.range, order: order)
        }
        stops = zip(built, orderedSlots).map { stop, slots in
            Stop(index: stop.index, slots: slots, choices: stop.choices)
        }
    }

    var finalPosition: Int {
        stops.count - 1
    }

    var finalCaret: Int {
        stops[finalPosition].slots[0].range.location
    }

    func nextPosition(after position: Int) -> Int {
        let candidates = stops.indices.dropFirst(position + 1).dropLast()
        return candidates.first(where: { stops[$0].isAlive }) ?? finalPosition
    }

    func previousPosition(before position: Int) -> Int? {
        stops.indices.prefix(position).last(where: { stops[$0].isAlive })
    }

    func firstPosition() -> Int {
        nextPosition(after: -1)
    }

    func primaryRange(of position: Int) -> NSRange? {
        stops[position].slots.first(where: \.isAlive)?.range
    }

    func slot(containing edit: NSRange, in position: Int) -> Int? {
        stops[position].slots.firstIndex {
            $0.isAlive && edit.location >= $0.range.location && NSMaxRange(edit) <= NSMaxRange($0.range)
        }
    }

    func contains(selection: NSRange, in position: Int) -> Bool {
        slot(containing: selection, in: position) != nil
    }

    func mirrorSlots(of position: Int, excluding slot: Int) -> [Int] {
        stops[position].slots.indices.filter { $0 != slot && stops[position].slots[$0].isAlive }
    }

    func range(of position: Int, slot: Int) -> NSRange {
        stops[position].slots[slot].range
    }

    mutating func apply(edit: NSRange, newLength: Int, stop sourceStop: Int, slot sourceSlot: Int) {
        let source = stops[sourceStop].slots[sourceSlot]
        for position in stops.indices {
            let isFinal = stops[position].isFinal
            for slotPosition in stops[position].slots.indices where stops[position].slots[slotPosition].isAlive {
                let slot = stops[position].slots[slotPosition]
                let isSource = position == sourceStop && slotPosition == sourceSlot
                let updated = Self.updated(
                    slot,
                    edit: edit,
                    newLength: newLength,
                    source: source,
                    isSource: isSource
                )
                if let updated {
                    stops[position].slots[slotPosition].range = updated
                } else if isFinal {
                    let collapsed = NSRange(location: edit.location + newLength, length: 0)
                    stops[position].slots[slotPosition].range = collapsed
                } else {
                    stops[position].slots[slotPosition].isAlive = false
                }
            }
        }
    }

    private static func updated(
        _ slot: Slot,
        edit: NSRange,
        newLength: Int,
        source: Slot,
        isSource: Bool
    ) -> NSRange? {
        let range = slot.range
        let delta = newLength - edit.length
        let rangeEnd = NSMaxRange(range)
        let editEnd = NSMaxRange(edit)
        let sourceEnd = NSMaxRange(source.range)
        let grown = NSRange(location: range.location, length: range.length + delta)
        let shifted = NSRange(location: range.location + delta, length: range.length)
        let containsSource = range.length > 0 && range.location <= source.range.location && sourceEnd <= rangeEnd
        if isSource || containsSource {
            return grown
        }
        if edit.length == 0 && range.length == 0 && edit.location == range.location {
            return slot.order > source.order ? shifted : range
        }
        if editEnd <= range.location {
            return shifted
        }
        if edit.location >= rangeEnd {
            return range
        }
        if edit.location >= range.location && editEnd <= rangeEnd {
            return grown
        }
        return nil
    }
}
