import Foundation

nonisolated enum CopyNaming {
    static func uniqueURL(
        for source: URL,
        isDirectory: Bool,
        in directory: URL,
        exists: (URL) -> Bool
    ) -> URL {
        let name = source.lastPathComponent
        let candidate = directory.appending(path: name)
        guard exists(candidate) else { return candidate }

        let fileExtension = isDirectory ? "" : source.pathExtension
        let stem = fileExtension.isEmpty ? name : String(name.dropLast(fileExtension.count + 1))
        let base = strippingCounter(from: stem)
        func numbered(_ counter: Int) -> URL {
            let numberedName = fileExtension.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(fileExtension)"
            return directory.appending(path: numberedName)
        }
        var counter = 1
        while exists(numbered(counter)) {
            counter += 1
        }
        return numbered(counter)
    }

    private static func strippingCounter(from stem: String) -> String {
        guard let range = stem.range(of: #" \(\d+\)$"#, options: .regularExpression),
              range.lowerBound > stem.startIndex else {
            return stem
        }
        return String(stem[..<range.lowerBound])
    }
}
