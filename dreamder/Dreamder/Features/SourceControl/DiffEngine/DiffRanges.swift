import Foundation

typealias DiffUnits = [UInt16]

nonisolated struct DiffRange: Sendable, Hashable {
    var start1: Int
    var end1: Int
    var start2: Int
    var end2: Int

    init(_ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int) {
        self.start1 = start1
        self.end1 = end1
        self.start2 = start2
        self.end2 = end2
    }

    var isEmpty: Bool { start1 == end1 && start2 == end2 }
    var length1: Int { end1 - start1 }
    var length2: Int { end2 - start2 }
}

nonisolated struct MergeRange: Sendable, Hashable {
    var start1: Int
    var end1: Int
    var start2: Int
    var end2: Int
    var start3: Int
    var end3: Int

    init(_ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int, _ start3: Int, _ end3: Int) {
        self.start1 = start1
        self.end1 = end1
        self.start2 = start2
        self.end2 = end2
        self.start3 = start3
        self.end3 = end3
    }

    var isEmpty: Bool { start1 == end1 && start2 == end2 && start3 == end3 }

    func start(_ side: ThreeSide) -> Int {
        switch side {
        case .left: return start1
        case .base: return start2
        case .right: return start3
        }
    }

    func end(_ side: ThreeSide) -> Int {
        switch side {
        case .left: return end1
        case .base: return end2
        case .right: return end3
        }
    }

    func range(_ side: ThreeSide) -> Range<Int> {
        let lower = start(side)
        return lower..<max(lower, end(side))
    }
}

nonisolated enum DiffSide: Sendable, Hashable {
    case left
    case right

    static func fromLeft(_ isLeft: Bool) -> DiffSide { isLeft ? .left : .right }

    var other: DiffSide { self == .left ? .right : .left }

    func select<T>(_ left: T, _ right: T) -> T { self == .left ? left : right }
}

nonisolated enum ThreeSide: Sendable, Hashable, CaseIterable {
    case left
    case base
    case right

    func select<T>(_ left: T, _ base: T, _ right: T) -> T {
        switch self {
        case .left: return left
        case .base: return base
        case .right: return right
        }
    }
}

nonisolated struct DiffTooBigError: Error, Sendable, Equatable {
    init() {}
}

nonisolated struct DiffFragment: Sendable, Hashable {
    var startOffset1: Int
    var endOffset1: Int
    var startOffset2: Int
    var endOffset2: Int

    init(_ startOffset1: Int, _ endOffset1: Int, _ startOffset2: Int, _ endOffset2: Int) {
        self.startOffset1 = startOffset1
        self.endOffset1 = endOffset1
        self.startOffset2 = startOffset2
        self.endOffset2 = endOffset2
    }

    var isEmpty: Bool { startOffset1 == endOffset1 && startOffset2 == endOffset2 }
}

nonisolated struct DiffBitSet: Sendable, Equatable {
    private var bits: [Bool]

    init(count: Int = 0) {
        bits = Array(repeating: false, count: max(count, 0))
    }

    subscript(index: Int) -> Bool {
        get { index >= 0 && index < bits.count ? bits[index] : false }
        set {
            guard index >= 0 else { return }
            ensureCount(index + 1)
            bits[index] = newValue
        }
    }

    mutating func set(from: Int, to: Int, value: Bool = true) {
        let lower = max(from, 0)
        guard lower < to else { return }
        ensureCount(to)
        for index in lower..<to {
            bits[index] = value
        }
    }

    private mutating func ensureCount(_ count: Int) {
        if bits.count < count {
            bits.append(contentsOf: repeatElement(false, count: count - bits.count))
        }
    }
}
