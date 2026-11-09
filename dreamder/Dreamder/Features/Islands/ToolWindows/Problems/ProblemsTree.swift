import Foundation

nonisolated struct ProblemCounts: Equatable, Sendable {
    var errors = 0
    var warnings = 0
    var information = 0

    var total: Int {
        errors + warnings + information
    }

    var summary: String {
        var parts: [String] = []
        if errors > 0 {
            parts.append("\(errors) \(errors == 1 ? "error" : "errors")")
        }
        if warnings > 0 {
            parts.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")")
        }
        if information > 0 {
            parts.append("\(information) \(information == 1 ? "weak warning" : "weak warnings")")
        }
        return parts.joined(separator: ", ")
    }

    static func of(_ diagnostics: [WorkspaceDiagnostic]) -> ProblemCounts {
        var counts = ProblemCounts()
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error:
                counts.errors += 1
            case .warning:
                counts.warnings += 1
            case .information, .hint:
                counts.information += 1
            }
        }
        return counts
    }
}

nonisolated struct ProblemFileNode: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let directory: String
    let diagnostics: [WorkspaceDiagnostic]

    var id: URL { url }

    var counts: ProblemCounts {
        ProblemCounts.of(diagnostics)
    }
}

nonisolated enum ProblemsTab: String, CaseIterable, Identifiable, Sendable {
    case file
    case project

    var id: String { rawValue }

    var baseTitle: String {
        switch self {
        case .file: "File"
        case .project: "Project Errors"
        }
    }

    func title(count: Int) -> String {
        count > 0 ? "\(baseTitle) (\(count))" : baseTitle
    }
}

nonisolated enum ProblemSeverityGroup: String, CaseIterable, Identifiable, Sendable {
    case errors
    case warnings
    case weakWarnings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .errors: "Errors"
        case .warnings: "Warnings"
        case .weakWarnings: "Weak Warnings and Hints"
        }
    }

    var iconName: String {
        switch self {
        case .errors: "status/error"
        case .warnings: "status/warning"
        case .weakWarnings: "status/info"
        }
    }

    static func group(of severity: WorkspaceDiagnostic.Severity) -> ProblemSeverityGroup {
        switch severity {
        case .error: .errors
        case .warning: .warnings
        case .information, .hint: .weakWarnings
        }
    }
}

nonisolated struct ProblemsSeverityFilter: Equatable, Sendable {
    private(set) var hidden: Set<ProblemSeverityGroup> = []

    func isShown(_ group: ProblemSeverityGroup) -> Bool {
        !hidden.contains(group)
    }

    func isShown(_ severity: WorkspaceDiagnostic.Severity) -> Bool {
        isShown(ProblemSeverityGroup.group(of: severity))
    }

    func toggling(_ group: ProblemSeverityGroup) -> ProblemsSeverityFilter {
        var copy = self
        if copy.hidden.contains(group) {
            copy.hidden.remove(group)
        } else {
            copy.hidden.insert(group)
        }
        return copy
    }

    func apply(to diagnostics: [WorkspaceDiagnostic]) -> [WorkspaceDiagnostic] {
        hidden.isEmpty ? diagnostics : diagnostics.filter { isShown($0.severity) }
    }
}

nonisolated enum ProblemsTreeBuilder {
    static func instances(
        diagnosticsByFile: [URL: [WorkspaceDiagnostic]],
        root: URL?,
        filter: ProblemsSeverityFilter = ProblemsSeverityFilter()
    ) -> [ProblemFileNode] {
        diagnosticsByFile.compactMap { url, diagnostics in
            node(url: url, diagnostics: diagnostics, root: root, filter: filter)
        }
        .sorted { lhs, rhs in
            let left = (lhs.directory, lhs.name)
            let right = (rhs.directory, rhs.name)
            if left.0 != right.0 {
                return left.0.localizedStandardCompare(right.0) == .orderedAscending
            }
            if left.1 != right.1 {
                return left.1.localizedStandardCompare(right.1) == .orderedAscending
            }
            return lhs.url.path < rhs.url.path
        }
    }

    static func node(
        url: URL,
        diagnostics: [WorkspaceDiagnostic],
        root: URL?,
        filter: ProblemsSeverityFilter = ProblemsSeverityFilter()
    ) -> ProblemFileNode? {
        let remaining = filter.apply(to: diagnostics)
        guard !remaining.isEmpty else { return nil }
        return ProblemFileNode(
            url: url,
            name: url.lastPathComponent,
            directory: relativeDirectory(of: url, root: root),
            diagnostics: sort(remaining)
        )
    }

    static func sort(_ diagnostics: [WorkspaceDiagnostic]) -> [WorkspaceDiagnostic] {
        diagnostics.sorted {
            ($0.severity.rawValue, $0.startLine, $0.startColumn, $0.message)
                < ($1.severity.rawValue, $1.startLine, $1.startColumn, $1.message)
        }
    }

    static func relativeDirectory(of url: URL, root: URL?) -> String {
        guard let root else { return "" }
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard !rootPath.isEmpty else { return "" }
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(base) else { return "" }
        let relative = String(path.dropFirst(base.count))
        guard !relative.isEmpty else { return "" }
        let directory = (relative as NSString).deletingLastPathComponent
        return directory
    }

    static func location(for diagnostic: WorkspaceDiagnostic) -> String {
        "\(diagnostic.startLine + 1):\(diagnostic.startColumn + 1)"
    }
}

nonisolated struct ProblemsEmptyState: Equatable, Sendable {
    let primary: String
    let secondary: String?

    static func file(hasLanguageServer: Bool, hasActiveFile: Bool = true) -> ProblemsEmptyState {
        guard hasActiveFile else {
            return ProblemsEmptyState(primary: "No problems found", secondary: "Open a file to see its problems")
        }
        return hasLanguageServer
            ? ProblemsEmptyState(primary: "No problems found", secondary: nil)
            : ProblemsEmptyState(
                primary: "No problems found",
                secondary: "No language server is running for this file"
            )
    }

    static let project = ProblemsEmptyState(primary: "No problems found", secondary: nil)
}

nonisolated extension WorkspaceDiagnostic.Severity {
    var iconName: String {
        switch self {
        case .error: "status/error"
        case .warning: "status/warning"
        case .information: "status/info"
        case .hint: "status/infoOutline"
        }
    }
}
