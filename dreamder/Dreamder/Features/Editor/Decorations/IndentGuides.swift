import Foundation

nonisolated enum IndentGuides {
    static func indentationColumns(of line: String, tabWidth: Int) -> Int {
        guard tabWidth > 0 else { return 0 }
        var columns = 0
        for character in line {
            switch character {
            case " ":
                columns += 1
            case "\t":
                columns += tabWidth - (columns % tabWidth)
            default:
                return columns
            }
        }
        return columns
    }

    static func levels(of lines: [String], tabWidth: Int) -> [Int] {
        guard tabWidth > 0 else { return lines.map { _ in 0 } }
        var result = [Int](repeating: 0, count: lines.count)
        var previous = 0
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result[index] = previous
            } else {
                previous = indentationColumns(of: line, tabWidth: tabWidth) / tabWidth
                result[index] = previous
            }
        }
        return result
    }

    static func block(containingLine index: Int, levels: [Int]) -> ClosedRange<Int>? {
        guard levels.indices.contains(index) else { return nil }
        let level = levels[index]
        guard level > 0 else { return nil }
        var lower = index
        var upper = index
        while lower > 0, levels[lower - 1] >= level {
            lower -= 1
        }
        while upper + 1 < levels.count, levels[upper + 1] >= level {
            upper += 1
        }
        return lower...upper
    }
}
