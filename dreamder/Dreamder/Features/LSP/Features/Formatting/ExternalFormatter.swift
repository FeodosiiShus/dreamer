import Foundation

nonisolated enum ExternalFormatterKind: String, Sendable, CaseIterable {
    case prettier
    case biome

    var binaryName: String {
        rawValue
    }

    var supportsRange: Bool {
        self == .prettier
    }

    var handledExtensions: Set<String> {
        switch self {
        case .prettier:
            return [
                "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts",
                "json", "jsonc", "json5", "css", "scss", "less", "html", "vue",
                "md", "markdown", "mdx", "yaml", "yml", "graphql", "gql"
            ]
        case .biome:
            return ["js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "json", "jsonc"]
        }
    }
}

nonisolated struct ExternalFormatter: Sendable, Equatable {
    let kind: ExternalFormatterKind
    let executable: URL
    let root: URL
    let fileURL: URL
    let selection: NSRange?

    var arguments: [String] {
        switch kind {
        case .prettier:
            var arguments = ["--stdin-filepath", fileURL.path(percentEncoded: false)]
            if let selection {
                arguments += [
                    "--range-start", String(selection.location),
                    "--range-end", String(NSMaxRange(selection))
                ]
            }
            return arguments
        case .biome:
            return ["format", "--stdin-file-path=\(fileURL.path(percentEncoded: false))"]
        }
    }
}

nonisolated enum ExternalFormatterChooser {
    static let binDirectoryComponents = ["node_modules", ".bin"]

    static func choose(
        root: URL,
        fileURL: URL,
        selection: NSRange?,
        fileExists: (String) -> Bool
    ) -> ExternalFormatter? {
        let fileExtension = fileURL.pathExtension.lowercased()
        let wantsRange = (selection?.length ?? 0) > 0
        for kind in ExternalFormatterKind.allCases {
            guard kind.handledExtensions.contains(fileExtension), !wantsRange || kind.supportsRange else { continue }
            let executable = binDirectoryComponents
                .reduce(root) { $0.appending(path: $1, directoryHint: .isDirectory) }
                .appending(path: kind.binaryName, directoryHint: .notDirectory)
            guard fileExists(executable.path(percentEncoded: false)) else { continue }
            return ExternalFormatter(
                kind: kind,
                executable: executable,
                root: root,
                fileURL: fileURL,
                selection: wantsRange ? selection : nil
            )
        }
        return nil
    }
}
