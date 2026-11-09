import Foundation

nonisolated struct FileTemplateContext: Sendable, Equatable {
    let name: String
    let packageName: String

    init(fileName: String, directory: URL) {
        name = (fileName as NSString).deletingPathExtension
        packageName = Self.packageName(forDirectory: directory)
    }

    static func packageName(forDirectory directory: URL) -> String {
        let scalars = directory.lastPathComponent.unicodeScalars
        var identifier = String(String.UnicodeScalarView(scalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" ? scalar : "_"
        }))
        if identifier.isEmpty {
            return "main"
        }
        if let first = identifier.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            identifier = "_" + identifier
        }
        return identifier
    }
}

nonisolated enum FileTemplateRenderer {
    static func render(_ template: String, context: FileTemplateContext) -> String {
        var result = ""
        var rest = Substring(template)
        while let opening = rest.range(of: "${") {
            result += rest[..<opening.lowerBound]
            let afterOpening = rest[opening.upperBound...]
            guard let closing = afterOpening.firstIndex(of: "}") else {
                result += rest[opening.lowerBound...]
                return result
            }
            let variable = afterOpening[..<closing]
            switch variable {
            case "NAME":
                result += context.name
            case "PACKAGE_NAME":
                result += context.packageName
            default:
                result += "${" + variable + "}"
            }
            rest = afterOpening[afterOpening.index(after: closing)...]
        }
        result += rest
        return result
    }
}

nonisolated struct FileTemplateStore: Sendable {
    static let overrideDirectory = ".dreamder/fileTemplates"

    static let builtIn: [String: String] = [
        "swift": "import Foundation\n",
        "ts": "",
        "js": "",
        "md": "# ${NAME}\n",
        "py": "",
        "go": "package ${PACKAGE_NAME}\n",
        "rs": ""
    ]

    let rootURL: URL

    func template(forExtension fileExtension: String) -> String? {
        let key = fileExtension.lowercased()
        guard !key.isEmpty else { return nil }
        let override = rootURL
            .appending(path: Self.overrideDirectory, directoryHint: .isDirectory)
            .appending(path: key + ".txt", directoryHint: .notDirectory)
        if let data = try? Data(contentsOf: override), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return Self.builtIn[key]
    }

    func contents(forFileNamed fileName: String, in directory: URL) -> Data? {
        guard let template = template(forExtension: (fileName as NSString).pathExtension), !template.isEmpty else {
            return nil
        }
        let context = FileTemplateContext(fileName: fileName, directory: directory)
        return Data(FileTemplateRenderer.render(template, context: context).utf8)
    }
}
