import Foundation

nonisolated struct MarkdownListIndentInfo: Equatable, Sendable {
    let indent: Int
    let markerLength: Int

    var subItemIndent: Int {
        indent + markerLength
    }

    func subItem(markerLength: Int) -> MarkdownListIndentInfo {
        MarkdownListIndentInfo(indent: subItemIndent, markerLength: markerLength)
    }
}

nonisolated extension MarkdownListStructure {
    func indentInfo(of item: Int) -> MarkdownListIndentInfo {
        MarkdownListIndentInfo(indent: items[item].innerIndent, markerLength: items[item].normalizedMarkerLength)
    }

    func lineIndentReplacement(line: Int, baseline: Int, newIndent: Int) -> MarkdownReplacement? {
        let start = text.lines[line].start
        let runEnd = text.indentRunEnd(line)
        let full = text.expandedIndent(line, tabWidth: tabWidth)
        let real = MarkdownTextLines.innerSpaces(of: full)
        if real < baseline || runEnd == text.lines[line].contentEnd {
            return nil
        }
        let replacement: [UInt16]
        if newIndent == baseline {
            replacement = full
        } else if newIndent > baseline {
            replacement = full + [UInt16](repeating: 32, count: newIndent - baseline)
        } else {
            replacement = Array(full.dropLast(baseline - newIndent))
        }
        return MarkdownReplacement(start: start, end: runEnd, text: String(decoding: replacement, as: UTF16.self))
    }

    func changeIndent(of item: Int, to newIndent: Int) -> [MarkdownReplacement] {
        let baseline = items[item].innerIndent
        return (items[item].line...items[item].lastLine).compactMap {
            lineIndentReplacement(line: $0, baseline: baseline, newIndent: newIndent)
        }
    }

    func unindentReplacements(of item: Int) -> [MarkdownReplacement]? {
        let value = items[item]
        guard let parent = value.parent else {
            let hasIndent = text.indentRunEnd(value.line) > text.lines[value.line].start
            return hasIndent ? changeIndent(of: item, to: 0) : nil
        }
        let outer = indentInfo(of: parent)
        let newIndent = value.innerIndent > outer.subItemIndent ? outer.subItemIndent : outer.indent
        return changeIndent(of: item, to: newIndent)
    }
}

nonisolated enum MarkdownListRenumber {
    static func replacements(
        in structure: MarkdownListStructure,
        list: Int,
        recursive: Bool,
        restart: Bool,
        sequentially: Bool
    ) -> [MarkdownReplacement] {
        guard let firstItem = structure.lists[list].items.first else { return [] }
        let firstIndent = structure.items[firstItem].innerIndent
        var result: [MarkdownReplacement] = []
        collect(
            structure: structure,
            list: list,
            listIndent: MarkdownListIndentInfo(indent: firstIndent, markerLength: 0),
            recursive: recursive,
            restart: restart,
            sequentially: sequentially,
            into: &result
        )
        return result
    }

    static func renumberInBulk(
        _ state: MarkdownTextState,
        listAtLine line: Int,
        recursive: Bool,
        restart: Bool,
        sequentially: Bool = true,
        tabWidth: Int = 4
    ) -> MarkdownTextState {
        let structure = MarkdownListStructure(text: MarkdownTextLines(units: state.units), tabWidth: tabWidth)
        guard line < structure.itemAtLine.count, let item = structure.itemAtLine[line] else { return state }
        let list = structure.items[item].list
        return state.applying(
            replacements(in: structure, list: list, recursive: recursive, restart: restart, sequentially: sequentially)
        )
    }

    private static func collect(
        structure: MarkdownListStructure,
        list: Int,
        listIndent: MarkdownListIndentInfo,
        recursive: Bool,
        restart: Bool,
        sequentially: Bool,
        into result: inout [MarkdownReplacement]
    ) {
        let members = structure.lists[list].items
        guard let first = members.first else { return }
        let firstPrefix = structure.items[first].prefix
        let start: Int? = switch firstPrefix.marker {
        case .bullet: nil
        case .ordered(let number, _): restart ? 1 : number
        }
        let flavor = firstPrefix.delimiter

        for (position, index) in members.enumerated() {
            let item = structure.items[index]
            let oldInfo = structure.indentInfo(of: index)
            let marker: String
            if let start {
                marker = "\(sequentially ? start + position : 1)\(flavor) "
            } else {
                marker = "\(flavor) "
            }
            let newInfo = listIndent.subItem(markerLength: marker.utf16.count)

            let lineStart = structure.lineStart(item.line)
            if let indentReplacement = structure.lineIndentReplacement(
                line: item.line,
                baseline: oldInfo.indent,
                newIndent: newInfo.indent
            ) {
                result.append(MarkdownReplacement(
                    start: lineStart,
                    end: lineStart + max(item.prefix.markerTokenEnd, structure.text.indentRunEnd(item.line) - lineStart),
                    text: indentReplacement.text + marker
                ))
            }

            var previousLine = item.line
            if recursive {
                for sublist in structure.sublists(of: index) {
                    guard let sublistFirst = structure.lists[sublist].items.first else { continue }
                    let sublistFirstLine = structure.items[sublistFirst].line
                    appendContentLines(
                        structure: structure,
                        from: previousLine + 1,
                        to: sublistFirstLine,
                        baseline: oldInfo.subItemIndent,
                        newIndent: newInfo.subItemIndent,
                        into: &result
                    )
                    collect(
                        structure: structure,
                        list: sublist,
                        listIndent: newInfo,
                        recursive: true,
                        restart: true,
                        sequentially: true,
                        into: &result
                    )
                    previousLine = structure.lastLine(ofList: sublist)
                }
            }
            appendContentLines(
                structure: structure,
                from: previousLine + 1,
                to: item.lastLine + 1,
                baseline: oldInfo.subItemIndent,
                newIndent: newInfo.subItemIndent,
                into: &result
            )
        }
    }

    private static func appendContentLines(
        structure: MarkdownListStructure,
        from first: Int,
        to end: Int,
        baseline: Int,
        newIndent: Int,
        into result: inout [MarkdownReplacement]
    ) {
        var line = first
        while line < end {
            if let replacement = structure.lineIndentReplacement(line: line, baseline: baseline, newIndent: newIndent) {
                result.append(replacement)
            }
            line += 1
        }
    }
}
