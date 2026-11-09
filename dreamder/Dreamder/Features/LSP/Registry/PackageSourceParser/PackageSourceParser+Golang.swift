//
//  PackageSourceParser+Golang.swift
//  Dreamder
//
//  Created by Abe Malla on 3/12/25.
//

nonisolated extension PackageSourceParser {
    static func parseGolangPackage(_ entry: RegistryItem) -> InstallationMethod {
        // Format: pkg:golang/PACKAGE@VERSION#SUBPATH?PARAMS
        let pkgPrefix = "pkg:golang/"
        let sourceId = entry.source.id.removingPercentEncoding ?? entry.source.id
        guard sourceId.hasPrefix(pkgPrefix) else { return .unknown }

        let pkgString = sourceId.dropFirst(pkgPrefix.count)
        guard let firstCharacter = pkgString.first, !"?#@".contains(firstCharacter) else { return .unknown }

        // Extract subpath first if present
        let subpathComponents = splitOnFirst(pkgString, separator: "#")
        let packageVersionParam = subpathComponents.head
        let subpath = subpathComponents.tail.map(String.init)

        let components = splitOnFirst(packageVersionParam, separator: "?")
        let packageVersion = components.head
        let parameters = components.tail.map(String.init) ?? ""

        let packageVersionParts = splitOnFirst(packageVersion, separator: "@")
        let packageName = String(packageVersionParts.head)
        let version = packageVersionParts.tail.map(String.init) ?? "latest"

        // Parse parameters as options
        var options: [String: String] = ["buildTool": "golang"]
        options["subpath"] = subpath
        var repositoryUrl: String?
        var gitReference: PackageSource.GitReference?

        let paramPairs = parameters.split(separator: "&")
        for pair in paramPairs {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }

            let key = String(keyValue[0])
            let value = String(keyValue[1])

            if key == "repository_url" {
                repositoryUrl = value
            } else if key == "rev" && value.lowercased() == "true" {
                gitReference = .revision(version)
            } else if key == "tag" && value.lowercased() == "true" {
                gitReference = .tag(version)
            } else {
                options[key] = value
            }
        }

        // For Go packages, the package name is often also the repository URL
        if repositoryUrl == nil {
            repositoryUrl = "https://\(packageName)"
        }

        let source = PackageSource(
            sourceId: sourceId,
            type: .golang,
            pkgName: packageName,
            entryName: entry.name,
            version: version,
            repositoryUrl: repositoryUrl,
            gitReference: gitReference,
            options: options
        )
        return .standardPackage(source: source)
    }
}
