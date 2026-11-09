import Foundation

nonisolated struct JsxMarkupScanner: Sendable {
    let markupRanges: [Range<Int>]

    init(units: [UInt16]) {
        var machine = JsxScanMachine(units: units)
        machine.run()
        markupRanges = machine.ranges
    }

    func isMarkup(at offset: Int) -> Bool {
        var low = 0
        var high = markupRanges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = markupRanges[middle]
            if offset < range.lowerBound {
                high = middle - 1
            } else if offset >= range.upperBound {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}

nonisolated private enum JsxFrameKind {
    case script
    case container
    case openingTag
    case closingTag
    case children
    case template
}

nonisolated private struct JsxFrame {
    var kind: JsxFrameKind
    var braceDepth = 0
    var expressionMayStart = true
    var containsMarkup = false
}

nonisolated private struct JsxScanMachine {
    let units: [UInt16]
    var stack = [JsxFrame(kind: .script)]
    var ranges: [Range<Int>] = []
    var markupStart: Int?

    private static let expressionKeywords: Set<String> = [
        "return", "default", "yield", "await", "case", "of", "in", "else", "do", "typeof", "void", "delete", "new",
        "throw", "instanceof",
    ]

    init(units: [UInt16]) {
        self.units = units
    }

    mutating func run() {
        var index = 0
        while index < units.count {
            switch stack[stack.count - 1].kind {
            case .script, .container:
                index = stepScript(at: index)
            case .openingTag, .closingTag:
                index = stepTag(at: index)
            case .children:
                index = stepChildren(at: index)
            case .template:
                index = stepTemplate(at: index)
            }
        }
        setMarkup(false, at: units.count)
    }

    private mutating func setMarkup(_ enabled: Bool, at offset: Int) {
        if enabled {
            if markupStart == nil { markupStart = offset }
        } else if let start = markupStart {
            if offset > start { ranges.append(start..<offset) }
            markupStart = nil
        }
    }

    private func unit(_ offset: Int) -> UInt16? {
        offset < units.count ? units[offset] : nil
    }

    private func isIdentifierStart(_ value: UInt16?) -> Bool {
        guard let value else { return false }
        return value == 0x5F || value == 0x24 || (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)
    }

    private func isIdentifierPart(_ value: UInt16) -> Bool {
        isIdentifierStart(value) || (value >= 0x30 && value <= 0x39) || value > 0x7F
    }

    private func isMarkupStart(at offset: Int) -> Bool {
        let next = unit(offset + 1)
        return next == 0x3E || isIdentifierStart(next)
    }

    private func lineEnd(from offset: Int) -> Int {
        var cursor = offset
        while cursor < units.count, units[cursor] != 0x0A, units[cursor] != 0x0D { cursor += 1 }
        return cursor
    }

    private func blockCommentEnd(from offset: Int) -> Int {
        var cursor = offset + 2
        while cursor < units.count {
            if units[cursor] == 0x2A, unit(cursor + 1) == 0x2F { return cursor + 2 }
            cursor += 1
        }
        return units.count
    }

    private func quotedEnd(from offset: Int, escapes: Bool) -> Int {
        let quote = units[offset]
        var cursor = offset + 1
        while cursor < units.count {
            let value = units[cursor]
            if escapes, value == 0x5C {
                cursor += 2
            } else if value == quote {
                return cursor + 1
            } else if escapes, value == 0x0A {
                return cursor
            } else {
                cursor += 1
            }
        }
        return units.count
    }

    private mutating func stepScript(at index: Int) -> Int {
        let top = stack.count - 1
        let value = units[index]
        switch value {
        case 0x20, 0x09, 0x0A, 0x0D:
            return index + 1
        case 0x2F where unit(index + 1) == 0x2F:
            return lineEnd(from: index)
        case 0x2F where unit(index + 1) == 0x2A:
            return blockCommentEnd(from: index)
        case 0x22, 0x27:
            stack[top].expressionMayStart = false
            return quotedEnd(from: index, escapes: true)
        case 0x60:
            stack.append(JsxFrame(kind: .template))
            return index + 1
        case 0x7B:
            stack[top].braceDepth += 1
            stack[top].expressionMayStart = true
            return index + 1
        case 0x7D:
            return closeBrace(at: index)
        case 0x3C where stack[top].expressionMayStart && isMarkupStart(at: index):
            stack[top].containsMarkup = true
            stack.append(JsxFrame(kind: .openingTag))
            setMarkup(true, at: index)
            return index + 1
        case 0x29, 0x5D:
            stack[top].expressionMayStart = false
            return index + 1
        default:
            guard isIdentifierPart(value) else {
                stack[top].expressionMayStart = true
                return index + 1
            }
            var end = index + 1
            while end < units.count, isIdentifierPart(units[end]) { end += 1 }
            let word = String(decoding: units[index..<end], as: UTF16.self)
            stack[top].expressionMayStart = Self.expressionKeywords.contains(word)
            return end
        }
    }

    private mutating func closeBrace(at index: Int) -> Int {
        let top = stack.count - 1
        if stack[top].braceDepth > 0 {
            stack[top].braceDepth -= 1
            stack[top].expressionMayStart = false
            return index + 1
        }
        guard stack[top].kind == .container else { return index + 1 }
        let containedMarkup = stack[top].containsMarkup
        stack.removeLast()
        let resumed = stack[stack.count - 1].kind
        if resumed == .children && containedMarkup {
            setMarkup(true, at: index)
        } else if resumed == .openingTag || resumed == .children {
            setMarkup(true, at: index + 1)
        }
        return index + 1
    }

    private mutating func stepTag(at index: Int) -> Int {
        let top = stack.count - 1
        let value = units[index]
        switch value {
        case 0x22, 0x27:
            return quotedEnd(from: index, escapes: false)
        case 0x7B:
            stack.append(JsxFrame(kind: .container))
            setMarkup(false, at: index + 1)
            return index + 1
        case 0x2F where unit(index + 1) == 0x3E:
            stack.removeLast()
            finishElement(at: index + 2)
            return index + 2
        case 0x3E:
            if stack[top].kind == .closingTag {
                stack.removeLast()
                finishElement(at: index + 1)
            } else {
                stack[top] = JsxFrame(kind: .children)
            }
            return index + 1
        default:
            return index + 1
        }
    }

    private mutating func finishElement(at offset: Int) {
        let top = stack.count - 1
        if stack[top].kind == .script || stack[top].kind == .container {
            stack[top].expressionMayStart = false
            setMarkup(false, at: offset)
        }
    }

    private mutating func stepChildren(at index: Int) -> Int {
        let top = stack.count - 1
        let value = units[index]
        if value == 0x7B {
            stack.append(JsxFrame(kind: .container))
            setMarkup(false, at: index + 1)
            return index + 1
        }
        guard value == 0x3C else { return index + 1 }
        if unit(index + 1) == 0x2F {
            stack[top] = JsxFrame(kind: .closingTag)
            return index + 2
        }
        if isMarkupStart(at: index) {
            stack.append(JsxFrame(kind: .openingTag))
        }
        return index + 1
    }

    private mutating func stepTemplate(at index: Int) -> Int {
        let value = units[index]
        if value == 0x5C {
            return index + 2
        }
        if value == 0x60 {
            stack.removeLast()
            let top = stack.count - 1
            stack[top].expressionMayStart = false
            return index + 1
        }
        if value == 0x24, unit(index + 1) == 0x7B {
            stack.append(JsxFrame(kind: .container))
            return index + 2
        }
        return index + 1
    }
}
