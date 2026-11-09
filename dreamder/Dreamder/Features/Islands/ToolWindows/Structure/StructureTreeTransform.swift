import Foundation

nonisolated struct StructureViewOptions: Equatable, Sendable {
    static let sortsAlphabeticallyKey = "dreamder.structure.sortsAlphabetically"
    static let groupsByKindKey = "dreamder.structure.groupsByKind"
    static let autoscrollsFromSourceKey = "dreamder.structure.autoscrollsFromSource"
    static let autoscrollsToSourceKey = "dreamder.structure.autoscrollsToSource"

    var sortsAlphabetically = false
    var groupsByKind = false
    var autoscrollsFromSource = true
    var autoscrollsToSource = false

    init() {}

    init(defaults: UserDefaults) {
        sortsAlphabetically = defaults.object(forKey: Self.sortsAlphabeticallyKey) as? Bool ?? false
        groupsByKind = defaults.object(forKey: Self.groupsByKindKey) as? Bool ?? false
        autoscrollsFromSource = defaults.object(forKey: Self.autoscrollsFromSourceKey) as? Bool ?? true
        autoscrollsToSource = defaults.object(forKey: Self.autoscrollsToSourceKey) as? Bool ?? false
    }

    func save(to defaults: UserDefaults) {
        defaults.set(sortsAlphabetically, forKey: Self.sortsAlphabeticallyKey)
        defaults.set(groupsByKind, forKey: Self.groupsByKindKey)
        defaults.set(autoscrollsFromSource, forKey: Self.autoscrollsFromSourceKey)
        defaults.set(autoscrollsToSource, forKey: Self.autoscrollsToSourceKey)
    }
}

nonisolated enum StructureKindGroup: Int, CaseIterable, Sendable {
    case namespaces
    case classes
    case constructors
    case functions
    case variables
    case other

    static let idPrefix = "group/"

    var title: String {
        switch self {
        case .namespaces: "Namespaces"
        case .classes: "Classes"
        case .constructors: "Constructors"
        case .functions: "Functions"
        case .variables: "Variables"
        case .other: "Other"
        }
    }

    var id: String { Self.idPrefix + title }

    init(_ kind: StructureSymbolKind) {
        switch kind {
        case .file, .module, .namespace, .package:
            self = .namespaces
        case .classType, .structType, .actorType, .enumType, .interface, .typeAlias, .extensionDecl,
             .typeParameter:
            self = .classes
        case .constructor:
            self = .constructors
        case .method, .function:
            self = .functions
        case .property, .field, .variable, .constant, .enumMember:
            self = .variables
        case .unknown:
            self = .other
        }
    }
}

nonisolated enum StructureTreeTransform {
    static func display(
        nodes: [StructureNode],
        options: StructureViewOptions,
        filter: String
    ) -> [StructureNode] {
        var result = nodes
        if options.sortsAlphabetically {
            result = sorted(result)
        }
        result = filtered(result, pattern: filter)
        if options.groupsByKind {
            result = grouped(result)
        }
        return result
    }

    static func isFiltering(_ pattern: String) -> Bool {
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func sorted(_ nodes: [StructureNode]) -> [StructureNode] {
        let ordered = nodes.enumerated().sorted { lhs, rhs in
            let left = lhs.element.name.lowercased()
            let right = rhs.element.name.lowercased()
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        return ordered.map { entry in
            var node = entry.element
            node.children = sorted(node.children)
            return node
        }
    }

    static func filtered(_ nodes: [StructureNode], pattern: String) -> [StructureNode] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nodes }
        let matcher = MinusculeMatcher(
            pattern: trimmed.hasPrefix("*") ? trimmed : "*" + trimmed,
            mode: .ignoreCase
        )
        return retainingMatches(nodes, matcher: matcher)
    }

    static func grouped(_ nodes: [StructureNode]) -> [StructureNode] {
        StructureKindGroup.allCases.compactMap { group in
            let members = nodes.filter { StructureKindGroup($0.kind) == group }
            guard let first = members.first else { return nil }
            return StructureNode(
                id: group.id,
                name: group.title,
                detail: "\(members.count)",
                kind: first.kind,
                line: first.line,
                column: first.column,
                children: members,
                isGroup: true
            )
        }
    }

    static func groupID(of node: StructureNode) -> String {
        StructureKindGroup(node.kind).id
    }

    static func find(_ id: String, in nodes: [StructureNode]) -> StructureNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let match = find(id, in: node.children) {
                return match
            }
        }
        return nil
    }

    private static func retainingMatches(_ nodes: [StructureNode], matcher: MinusculeMatcher) -> [StructureNode] {
        nodes.compactMap { node in
            let children = retainingMatches(node.children, matcher: matcher)
            guard matcher.matches(node.name) || !children.isEmpty else { return nil }
            var kept = node
            kept.children = children
            return kept
        }
    }
}

nonisolated enum StructureCaretLine {
    static func line(offset: Int, in text: String) -> Int {
        let nsText = text as NSString
        let location = min(max(offset, 0), nsText.length)
        var line = 1
        var searchRange = NSRange(location: 0, length: location)
        while true {
            let found = nsText.range(of: "\n", options: .literal, range: searchRange)
            guard found.location != NSNotFound else { break }
            line += 1
            searchRange = NSRange(location: found.upperBound, length: location - found.upperBound)
        }
        return line
    }
}
