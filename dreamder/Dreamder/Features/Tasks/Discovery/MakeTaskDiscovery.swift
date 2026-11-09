import Foundation

nonisolated enum MakeTaskDiscovery {
    private static let manifestNames = ["Makefile", "makefile", "GNUmakefile"]
    private static let phonyDirective = ".PHONY"
    private static let forbiddenTargetCharacters = CharacterSet(charactersIn: "%$=/")

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        guard let manifestName = manifestNames.first(where: { directory.fileNames.contains($0) }),
              let text = try? String(contentsOf: directory.fileURL(manifestName), encoding: .utf8) else { return nil }
        let lines = logicalLines(in: text)
        let phony = unique(lines.flatMap(phonyTargets))
        let targets = phony.isEmpty ? unique(lines.flatMap(ruleTargets)) : phony
        return directory.group(
            kind: .make,
            manifestName: manifestName,
            entries: targets.map { TaskEntry(command: "make \($0)") }
        )
    }

    private static func logicalLines(in text: String) -> [String] {
        var lines: [String] = []
        var pending = ""
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.hasSuffix("\\") {
                pending += String(line.dropLast()) + " "
            } else {
                lines.append(pending + String(line))
                pending = ""
            }
        }
        lines.append(pending)
        return lines
    }

    private static func phonyTargets(in line: String) -> [String] {
        guard line.hasPrefix(phonyDirective) else { return [] }
        let remainder = line.dropFirst(phonyDirective.count).drop(while: \.isWhitespace)
        guard remainder.first == ":" else { return [] }
        return remainder.dropFirst()
            .prefix(while: { $0 != "#" })
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter(isValidTarget)
    }

    private static func ruleTargets(in line: String) -> [String] {
        guard let first = line.first, !first.isWhitespace, first != "#",
              !line.contains("="),
              let colon = line.firstIndex(of: ":") else { return [] }
        return line[..<colon]
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter(isValidTarget)
    }

    private static func isValidTarget(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.rangeOfCharacter(from: forbiddenTargetCharacters) == nil
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
