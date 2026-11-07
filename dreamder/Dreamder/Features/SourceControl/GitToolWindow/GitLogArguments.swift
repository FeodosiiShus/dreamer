import Foundation

nonisolated struct GitLogParameters: Hashable, Sendable {
    let configParameters: [String]
    let filterParameters: [String]
}

nonisolated enum GitLogArguments {
    static let logAll = ["HEAD", "--branches", "--remotes", "--tags"]
    static let headReference = "HEAD"

    static func parameters(
        filters: GitLogFilterCollection,
        options: GitLogOptions = GitLogOptions(),
        maxCount: Int?,
        existingBranches: [String],
        userResolver: GitLogUserResolver = GitLogUserResolver(),
        headIsResolvable: Bool = true
    ) -> GitLogParameters? {
        let branchLike = branchLikeParameters(
            filters: filters,
            existingBranches: existingBranches,
            headIsResolvable: headIsResolvable
        )
        if branchLike.isEmpty && (filters.branch != nil || filters.revision != nil || filters.range != nil) {
            return nil
        }

        var configParameters: [String] = []
        var filterParameters = branchLike

        if let date = filters.date {
            if let after = date.after {
                filterParameters.append(parameter("after", gitDate(after)))
            }
            if let before = date.before {
                filterParameters.append(parameter("before", gitDate(before)))
            }
        }

        let textFilter = filters.text
        let regexp = textFilter?.isRegex ?? true
        let caseSensitive = textFilter?.matchesCase ?? false
        appendTextFilterParameters(textFilter?.text, regexp: regexp, caseSensitive: caseSensitive, to: &filterParameters)

        if let userFilter = filters.user {
            let users = userFilter.users(resolver: userResolver)
            if users.isEmpty {
                return nil
            }
            let names = users.map(\.exactString)
            if regexp {
                filterParameters.append(parameter("author", names.map(GitLogUserNames.extendedRegex(for:)).joined(separator: "|")))
            } else {
                filterParameters.append(contentsOf: names.map { parameter("author", GitLogUserNames.escapeBackSlashes($0)) })
            }
            configParameters.append("log.mailmap=false")
        }

        if let maxCount, maxCount > 0 {
            filterParameters.append(parameter("max-count", String(maxCount)))
        }

        if options.firstParent {
            filterParameters.append("--first-parent")
        }

        if let parent = filters.parent, !parent.matchesAll {
            if parent.hasLowerBound {
                filterParameters.append("--min-parents=\(parent.minParents)")
            }
            if parent.hasUpperBound {
                filterParameters.append("--max-parents=\(parent.maxParents)")
            }
        }

        if let structure = filters.structure, !structure.paths.isEmpty {
            filterParameters.append("--full-history")
            filterParameters.append("--simplify-merges")
            filterParameters.append("--")
            filterParameters.append(contentsOf: structure.paths)
        }

        return GitLogParameters(configParameters: configParameters, filterParameters: filterParameters)
    }

    static func arguments(parameters: GitLogParameters, format: String) -> [String] {
        var arguments: [String] = []
        for config in parameters.configParameters {
            arguments.append("-c")
            arguments.append(config)
        }
        arguments.append(contentsOf: ["log", "--date-order", "-z", "--format=\(format)"])
        arguments.append(contentsOf: parameters.filterParameters)
        return arguments
    }

    static func branchLikeParameters(
        filters: GitLogFilterCollection,
        existingBranches: [String],
        headIsResolvable: Bool
    ) -> [String] {
        let branchFilter = filters.branch
        let revisionFilter = filters.revision
        let rangeFilter = filters.range
        if branchFilter == nil && revisionFilter == nil && rangeFilter == nil {
            return headIsResolvable ? logAll : Array(logAll.dropFirst())
        }

        var result: [String] = []

        if let branchFilter {
            for name in existingBranches + [headReference] where branchFilter.matches(name) {
                result.append(name)
            }
        }

        if let revisionFilter {
            result.append(contentsOf: revisionFilter.heads)
        }

        if let rangeFilter {
            for range in rangeFilter.ranges {
                result.append("\(range.exclusiveRef)..\(range.inclusiveRef)")
            }
        }
        return result
    }

    static func gitDate(_ date: Date) -> String {
        "\(Int(date.timeIntervalSince1970)) +0000"
    }

    private static func appendTextFilterParameters(
        _ text: String?,
        regexp: Bool,
        caseSensitive: Bool,
        to filterParameters: inout [String]
    ) {
        if let text {
            filterParameters.append(parameter("grep", text))
        }
        filterParameters.append(regexp ? "--extended-regexp" : "--fixed-strings")
        if !caseSensitive {
            filterParameters.append("--regexp-ignore-case")
        }
    }

    private static func parameter(_ name: String, _ value: String) -> String {
        "--\(name)=\(value)"
    }
}
