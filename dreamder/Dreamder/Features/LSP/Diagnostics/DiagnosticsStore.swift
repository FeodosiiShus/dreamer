import Foundation

nonisolated struct WorkspaceDiagnostic: Identifiable, Hashable, Sendable {
    nonisolated enum Severity: Int, Comparable, CaseIterable, Sendable {
        case error = 1
        case warning = 2
        case information = 3
        case hint = 4

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let fileURL: URL
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
    let severity: Severity
    let message: String
    let source: String?
    let code: String?

    var id: String {
        "\(fileURL.path):\(startLine):\(startColumn):\(endLine):\(endColumn):\(severity.rawValue):\(message)"
    }
}

final class DiagnosticsStore: ObservableObject {
    @Published private(set) var diagnosticsByFile: [URL: [WorkspaceDiagnostic]] = [:]

    var files: [URL] {
        diagnosticsByFile.keys.sorted { $0.path < $1.path }
    }

    var errorCount: Int {
        count(of: .error)
    }

    var warningCount: Int {
        count(of: .warning)
    }

    func diagnostics(for url: URL) -> [WorkspaceDiagnostic] {
        diagnosticsByFile[url.standardizedFileURL] ?? []
    }

    func replace(_ diagnostics: [WorkspaceDiagnostic], for url: URL) {
        let key = url.standardizedFileURL
        let sorted = diagnostics.sorted {
            ($0.severity, $0.startLine, $0.startColumn) < ($1.severity, $1.startLine, $1.startColumn)
        }
        if sorted.isEmpty {
            diagnosticsByFile.removeValue(forKey: key)
        } else {
            diagnosticsByFile[key] = sorted
        }
    }

    func clear(_ url: URL) {
        diagnosticsByFile.removeValue(forKey: url.standardizedFileURL)
    }

    func clearAll() {
        diagnosticsByFile.removeAll()
    }

    private func count(of severity: WorkspaceDiagnostic.Severity) -> Int {
        diagnosticsByFile.values.reduce(0) { total, items in
            total + items.filter { $0.severity == severity }.count
        }
    }
}
