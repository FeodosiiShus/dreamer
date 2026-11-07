//
//  PackageSourceParser+Gem.swift
//  Dreamder
//
//  Created by Abe Malla on 3/12/25.
//

extension PackageSourceParser {
    static func parseRubyGem(_ entry: RegistryItem) -> InstallationMethod {
        // Format: pkg:gem/PACKAGE@VERSION?PARAMS
        let pkgPrefix = "pkg:gem/"
        let sourceId = entry.source.id.removingPercentEncoding ?? entry.source.id
        guard sourceId.hasPrefix(pkgPrefix) else { return .unknown }

        let pkgString = sourceId.dropFirst(pkgPrefix.count)
        guard let firstCharacter = pkgString.first, !"?@".contains(firstCharacter) else { return .unknown }

        let components = pkgString.split(separator: "?", maxSplits: 1)
        guard let packageVersionString = components.first else { return .unknown }
        let packageVersion = String(packageVersionString)
        let parameters = components.count > 1 ? String(components[1]) : ""

        let packageVersionParts = packageVersion.split(separator: "@", maxSplits: 1)
        guard let packageNameString = packageVersionParts.first else { return .unknown }

        let packageName = String(packageNameString)
        let version = packageVersionParts.count > 1 ? String(packageVersionParts[1]) : "latest"

        // Parse parameters as options
        var options: [String: String] = ["buildTool": "gem"]
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

        let source = PackageSource(
            sourceId: sourceId,
            type: .gem,
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
