import Foundation

nonisolated struct EditorConfigResolver: Sendable {
    private static let configFileName = ".editorconfig"
    private static let maxKeyLength = 1024
    private static let maxValueLength = 4096
    private static let maxSectionNameLength = 1024
    private static let lowercasedValueKeys: Set<String> = [
        "root", "indent_style", "indent_size", "tab_width", "end_of_line",
        "charset", "trim_trailing_whitespace", "insert_final_newline", "max_line_length"
    ]

    private let readFile: @Sendable (URL) -> String?

    init(readFile: @escaping @Sendable (URL) -> String? = EditorConfigResolver.readFromDisk) {
        self.readFile = readFile
    }

    func properties(for fileURL: URL) -> EditorConfigProperties {
        let components = fileURL.standardizedFileURL.pathComponents
        var layers: [(file: EditorConfigFile, relativePath: String)] = []
        var depth = components.count - 1
        while depth >= 1 {
            let directory = URL(
                filePath: NSString.path(withComponents: Array(components[..<depth])),
                directoryHint: .isDirectory
            )
            depth -= 1
            let configURL = directory.appending(path: Self.configFileName, directoryHint: .notDirectory)
            guard let text = readFile(configURL) else { continue }
            let file = Self.parse(text)
            layers.append((file, components[(depth + 1)...].joined(separator: "/")))
            if file.isRoot { break }
        }
        var values: [String: String] = [:]
        for layer in layers.reversed() {
            for section in layer.file.sections
            where EditorConfigGlob.matches(pattern: section.name, relativePath: layer.relativePath) {
                for pair in section.pairs {
                    values[pair.key] = pair.value
                }
            }
        }
        values = values.filter { $0.value.lowercased() != "unset" }
        return EditorConfigProperties(resolving: values)
    }

    static func parse(_ text: String) -> EditorConfigFile {
        var file = EditorConfigFile(isRoot: false, sections: [])
        var inPreamble = true
        var skippingSection = false
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : Substring(text)
        let lines = body.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = line.first, first != "#", first != ";" else { continue }
            if first == "[" {
                guard line.last == "]" else { continue }
                inPreamble = false
                let name = String(line.dropFirst().dropLast())
                skippingSection = name.count > maxSectionNameLength
                if !skippingSection {
                    file.sections.append(EditorConfigFile.Section(name: name, pairs: []))
                }
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.count <= maxKeyLength, rawValue.count <= maxValueLength else { continue }
            let value = lowercasedValueKeys.contains(key) ? rawValue.lowercased() : rawValue
            if inPreamble {
                if key == "root" {
                    file.isRoot = value == "true"
                }
                continue
            }
            guard !skippingSection, let last = file.sections.indices.last else { continue }
            file.sections[last].pairs.append(EditorConfigFile.Pair(key: key, value: value))
        }
        return file
    }

    static func readFromDisk(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
