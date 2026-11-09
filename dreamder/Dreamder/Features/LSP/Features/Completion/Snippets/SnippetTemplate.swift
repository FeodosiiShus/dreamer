import Foundation

nonisolated struct SnippetTemplate: Sendable, Equatable {
    nonisolated struct TabStop: Sendable, Equatable {
        let index: Int
        let ranges: [NSRange]
        let choices: [String]
    }

    let text: String
    let tabStops: [TabStop]
    let finalCaret: Int

    init(text: String, tabStops: [TabStop] = [], finalCaret: Int? = nil) {
        self.text = text
        self.tabStops = tabStops
        self.finalCaret = finalCaret ?? text.utf16.count
    }

    init(parsing source: String, variables: SnippetVariableContext = SnippetVariableContext()) {
        var layout = SnippetLayout(nodes: SnippetParser.parse(source), variables: variables)
        layout.run()
        self.init(text: layout.text, tabStops: layout.tabStops(), finalCaret: layout.finalCaret)
    }
}

nonisolated private struct SnippetLayout {
    struct Occurrence {
        let range: NSRange
        let isDefinition: Bool
    }

    struct Definition {
        enum Content {
            case children([SnippetNode])
            case choice(String)

            init?(children: [SnippetNode], choices: [String]) {
                if !children.isEmpty {
                    self = .children(children)
                } else if let first = choices.first {
                    self = .choice(first)
                } else {
                    return nil
                }
            }
        }

        let content: Content
        let choices: [String]
    }

    struct OccurrenceGroup {
        var first: Occurrence
        var rest: [Occurrence] = []

        var all: [Occurrence] {
            [first] + rest
        }
    }

    let nodes: [SnippetNode]
    let variables: SnippetVariableContext
    private(set) var text = ""
    private var length = 0
    private var definitions: [Int: Definition] = [:]
    private var claimedDefinitions: Set<Int> = []
    private var occurrences: [Int: OccurrenceGroup] = [:]
    private var caret: Int?

    var finalCaret: Int {
        caret ?? length
    }

    init(nodes: [SnippetNode], variables: SnippetVariableContext) {
        self.nodes = nodes
        self.variables = variables
        collectDefinitions(in: nodes)
    }

    mutating func run() {
        emit(nodes, visiting: [])
    }

    func tabStops() -> [SnippetTemplate.TabStop] {
        occurrences.sorted { $0.key < $1.key }.map { entry in
            var others = entry.value.all
            let primaryPosition = others.firstIndex(where: \.isDefinition) ?? 0
            let primary = others.remove(at: primaryPosition)
            let ranges = [primary.range] + others.map(\.range).sorted { $0.location < $1.location }
            return SnippetTemplate.TabStop(
                index: entry.key,
                ranges: ranges,
                choices: definitions[entry.key]?.choices ?? []
            )
        }
    }

    private mutating func collectDefinitions(in nodes: [SnippetNode]) {
        for node in nodes {
            switch node {
            case .text:
                continue
            case let .tabStop(index, children, choices):
                if index > 0, definitions[index] == nil,
                   let content = Definition.Content(children: children, choices: choices) {
                    definitions[index] = Definition(content: content, choices: choices)
                }
                collectDefinitions(in: children)
            case let .variable(_, children):
                collectDefinitions(in: children)
            }
        }
    }

    private mutating func append(_ string: String) {
        text += string
        length += string.utf16.count
    }

    private mutating func emit(_ nodes: [SnippetNode], visiting: Set<Int>) {
        for node in nodes {
            switch node {
            case let .text(string):
                append(string)
            case let .tabStop(index, children, choices):
                emitTabStop(index: index, children: children, choices: choices, visiting: visiting)
            case let .variable(name, children):
                let value = variables.value(for: name)
                if let value, !value.isEmpty {
                    append(value)
                } else if !children.isEmpty {
                    emit(children, visiting: visiting)
                } else if value == nil {
                    append(name)
                }
            }
        }
    }

    private mutating func emitTabStop(
        index: Int,
        children: [SnippetNode],
        choices: [String],
        visiting: Set<Int>
    ) {
        let start = length
        guard index > 0 else {
            if caret == nil {
                caret = start
            }
            emit(children, visiting: visiting)
            return
        }
        let content = Definition.Content(children: children, choices: choices)
        var isDefinition = false
        if let content, claimedDefinitions.insert(index).inserted {
            isDefinition = true
            switch content {
            case let .children(nodes):
                emit(nodes, visiting: visiting.union([index]))
            case let .choice(first):
                append(first)
            }
        } else {
            append(value(of: index, visiting: visiting))
        }
        let range = NSRange(location: start, length: length - start)
        record(Occurrence(range: range, isDefinition: isDefinition), for: index)
    }

    private mutating func record(_ occurrence: Occurrence, for index: Int) {
        if var group = occurrences[index] {
            group.rest.append(occurrence)
            occurrences[index] = group
        } else {
            occurrences[index] = OccurrenceGroup(first: occurrence)
        }
    }

    private func value(of index: Int, visiting: Set<Int>) -> String {
        guard !visiting.contains(index), let definition = definitions[index] else { return "" }
        switch definition.content {
        case let .children(nodes):
            return flatten(nodes, visiting: visiting.union([index]))
        case let .choice(first):
            return first
        }
    }

    private func flatten(_ nodes: [SnippetNode], visiting: Set<Int>) -> String {
        var result = ""
        for node in nodes {
            switch node {
            case let .text(string):
                result += string
            case let .tabStop(index, children, choices):
                if index == 0 {
                    result += flatten(children, visiting: visiting)
                } else if !children.isEmpty {
                    result += flatten(children, visiting: visiting.union([index]))
                } else if let first = choices.first {
                    result += first
                } else {
                    result += value(of: index, visiting: visiting)
                }
            case let .variable(name, children):
                let value = variables.value(for: name)
                if let value, !value.isEmpty {
                    result += value
                } else if !children.isEmpty {
                    result += flatten(children, visiting: visiting)
                } else if value == nil {
                    result += name
                }
            }
        }
        return result
    }
}
