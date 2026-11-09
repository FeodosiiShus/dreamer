import Foundation

nonisolated struct MyersLCS {
    private let first: [Int]
    private let second: [Int]
    private let start1: Int
    private let count1: Int
    private let start2: Int
    private let count2: Int
    private(set) var changes1: DiffBitSet
    private(set) var changes2: DiffBitSet
    private var forwardV: [Int]
    private var backwardV: [Int]

    static let deltaThresholdSize = 20000

    init(
        first: [Int],
        second: [Int],
        start1: Int,
        count1: Int,
        start2: Int,
        count2: Int,
        changes1: DiffBitSet,
        changes2: DiffBitSet
    ) {
        var markedChanges1 = changes1
        var markedChanges2 = changes2
        markedChanges1.set(from: start1, to: start1 + count1)
        markedChanges2.set(from: start2, to: start2 + count2)
        let total = count1 + count2
        self.first = first
        self.second = second
        self.start1 = start1
        self.count1 = count1
        self.start2 = start2
        self.count2 = count2
        self.changes1 = markedChanges1
        self.changes2 = markedChanges2
        self.forwardV = Array(repeating: 0, count: total + 2)
        self.backwardV = Array(repeating: 0, count: total + 2)
    }

    init(first: [Int], second: [Int]) {
        self.init(
            first: first,
            second: second,
            start1: 0,
            count1: first.count,
            start2: 0,
            count2: second.count,
            changes1: DiffBitSet(count: first.count),
            changes2: DiffBitSet(count: second.count)
        )
    }

    mutating func executeLinear() throws {
        let threshold = 20000 + 10 * Int(Double(count1 + count2).squareRoot())
        try execute(threshold: threshold, throwsWhenTooBig: false)
    }

    mutating func execute() throws {
        try execute(threshold: count1 + count2, throwsWhenTooBig: false)
    }

    mutating func executeWithThreshold(limit: Int = Self.deltaThresholdSize) throws {
        let threshold = max(limit + 10 * Int(Double(count1 + count2).squareRoot()), limit)
        try execute(threshold: threshold, throwsWhenTooBig: true)
    }

    private mutating func execute(threshold: Int, throwsWhenTooBig: Bool) throws {
        if count1 == 0 || count2 == 0 { return }
        try execute(
            oldStart: 0,
            oldEnd: count1,
            newStart: 0,
            newEnd: count2,
            differenceEstimate: min(threshold, count1 + count2),
            throwsWhenTooBig: throwsWhenTooBig
        )
    }

    private mutating func execute(
        oldStart: Int,
        oldEnd: Int,
        newStart: Int,
        newEnd: Int,
        differenceEstimate: Int,
        throwsWhenTooBig: Bool
    ) throws {
        try Task.checkCancellation()
        guard oldStart < oldEnd && newStart < newEnd else { return }

        let oldLength = oldEnd - oldStart
        let newLength = newEnd - newStart
        forwardV[newLength + 1] = 0
        backwardV[newLength + 1] = 0
        let halfD = (differenceEstimate + 1) / 2
        var xx = -1
        var kk = -1
        var td = -1

        search: for d in 0...halfD {
            let low = newLength + max(-d, -newLength + ((d ^ newLength) & 1))
            let high = newLength + min(d, oldLength - ((d ^ oldLength) & 1))

            var k = low
            while k <= high {
                var x: Int
                if k == low || (k != high && forwardV[k - 1] < forwardV[k + 1]) {
                    x = forwardV[k + 1]
                } else {
                    x = forwardV[k - 1] + 1
                }
                let y = x - k + newLength
                x += commonLengthForward(
                    oldStart + x,
                    newStart + y,
                    min(oldEnd - oldStart - x, newEnd - newStart - y)
                )
                forwardV[k] = x
                k += 2
            }

            if (oldLength - newLength) % 2 != 0 {
                k = low
                while k <= high {
                    if oldLength - (d - 1) <= k && k <= oldLength + (d - 1) {
                        if forwardV[k] + backwardV[newLength + oldLength - k] >= oldLength {
                            xx = forwardV[k]
                            kk = k
                            td = 2 * d - 1
                            break search
                        }
                    }
                    k += 2
                }
            }

            k = low
            while k <= high {
                var x: Int
                if k == low || (k != high && backwardV[k - 1] < backwardV[k + 1]) {
                    x = backwardV[k + 1]
                } else {
                    x = backwardV[k - 1] + 1
                }
                let y = x - k + newLength
                x += commonLengthBackward(
                    oldEnd - 1 - x,
                    newEnd - 1 - y,
                    min(oldEnd - oldStart - x, newEnd - newStart - y)
                )
                backwardV[k] = x
                k += 2
            }

            if (oldLength - newLength) % 2 == 0 {
                k = low
                while k <= high {
                    if oldLength - d <= k && k <= oldLength + d {
                        if forwardV[oldLength + newLength - k] + backwardV[k] >= oldLength {
                            xx = oldLength - backwardV[k]
                            kk = oldLength + newLength - k
                            td = 2 * d
                            break search
                        }
                    }
                    k += 2
                }
            }
        }

        if td > 1 {
            let yy = xx - kk + newLength
            let oldDiff = (td + 1) / 2
            if 0 < xx && 0 < yy {
                try execute(
                    oldStart: oldStart,
                    oldEnd: oldStart + xx,
                    newStart: newStart,
                    newEnd: newStart + yy,
                    differenceEstimate: oldDiff,
                    throwsWhenTooBig: throwsWhenTooBig
                )
            }
            if oldStart + xx < oldEnd && newStart + yy < newEnd {
                try execute(
                    oldStart: oldStart + xx,
                    oldEnd: oldEnd,
                    newStart: newStart + yy,
                    newEnd: newEnd,
                    differenceEstimate: td - oldDiff,
                    throwsWhenTooBig: throwsWhenTooBig
                )
            }
        } else if td >= 0 {
            var x = oldStart
            var y = newStart
            while x < oldEnd && y < newEnd {
                let commonLength = commonLengthForward(x, y, min(oldEnd - x, newEnd - y))
                if commonLength > 0 {
                    addUnchanged(x, y, commonLength)
                    x += commonLength
                    y += commonLength
                } else if oldEnd - oldStart > newEnd - newStart {
                    x += 1
                } else {
                    y += 1
                }
            }
        } else if throwsWhenTooBig {
            throw DiffTooBigError()
        }
    }

    private mutating func addUnchanged(_ offset1: Int, _ offset2: Int, _ count: Int) {
        changes1.set(from: start1 + offset1, to: start1 + offset1 + count, value: false)
        changes2.set(from: start2 + offset2, to: start2 + offset2 + count, value: false)
    }

    private func commonLengthForward(_ oldIndex: Int, _ newIndex: Int, _ maxLength: Int) -> Int {
        let limit = min(maxLength, min(count1 - oldIndex, count2 - newIndex))
        var x = oldIndex
        var y = newIndex
        while x - oldIndex < limit && first[start1 + x] == second[start2 + y] {
            x += 1
            y += 1
        }
        return x - oldIndex
    }

    private func commonLengthBackward(_ oldIndex: Int, _ newIndex: Int, _ maxLength: Int) -> Int {
        let limit = min(maxLength, min(oldIndex, newIndex) + 1)
        var x = oldIndex
        var y = newIndex
        while oldIndex - x < limit && first[start1 + x] == second[start2 + y] {
            x -= 1
            y -= 1
        }
        return oldIndex - x
    }
}
