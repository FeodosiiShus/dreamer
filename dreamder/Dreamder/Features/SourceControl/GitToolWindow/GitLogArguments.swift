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
        let hasRevisionSelection = selectsRevisions(filters)
        guard let revisions = branchLikeParameters(
            filters: filters,
            existingBranches: existingBranches,
            headIsResolvable: headIsResolvable
        ), !(hasRevisionSelection && revisions.isEmpty) else {
            return nil
        }

        var configParameters: [String] = []
        var filterParameters = hasRevisionSelection ? [] : revisions
        appendDateParameters(filters.date, to: &filterParameters)

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

        appendParentParameters(filters.parent, to: &filterParameters)
        appendRevisionsAndPaths(
            revisions: hasRevisionSelection ? revisions : [],
            paths: filters.structure?.paths ?? [],
            to: &filterParameters
        )

        return GitLogParameters(configParameters: configParameters, filterParameters: filterParameters)
    }

    static func arguments(parameters: GitLogParameters, format: String) -> [String] {
        var arguments: [String] = []
        for config in parameters.configParameters {
            arguments.append("-c")
            arguments.append(config)
        }
        arguments.append(contentsOf: ["log", "--date-order", "-z", "--decorate=full", "--format=\(format)"])
        arguments.append(contentsOf: parameters.filterParameters)
        return arguments
    }

    static func selectsRevisions(_ filters: GitLogFilterCollection) -> Bool {
        filters.branch != nil || filters.revision != nil || filters.range != nil
    }

    static func branchLikeParameters(
        filters: GitLogFilterCollection,
        existingBranches: [String],
        headIsResolvable: Bool
    ) -> [String]? {
        let branchFilter = filters.branch
        let revisionFilter = filters.revision
        let rangeFilter = filters.range
        if !selectsRevisions(filters) {
            return headIsResolvable ? logAll : Array(logAll.dropFirst())
        }

        let suppliedRefs = (revisionFilter?.heads ?? [])
            + (rangeFilter?.ranges.flatMap { [$0.exclusiveRef, $0.inclusiveRef] } ?? [])
        guard !suppliedRefs.contains(where: { $0.hasPrefix("-") }) else { return nil }

        var result: [String] = []

        if let branchFilter {
            for name in existingBranches + [headReference] where branchFilter.matches(name) && !name.hasPrefix("-") {
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

    private static func appendDateParameters(_ date: GitLogDateFilter?, to filterParameters: inout [String]) {
        guard let date else { return }
        if let after = date.after {
            filterParameters.append(parameter("after", gitDate(after)))
        }
        if let before = date.before {
            filterParameters.append(parameter("before", gitDate(before)))
        }
    }

    private static func appendParentParameters(_ parent: GitLogParentFilter?, to filterParameters: inout [String]) {
        guard let parent, !parent.matchesAll else { return }
        if parent.hasLowerBound {
            filterParameters.append("--min-parents=\(parent.minParents)")
        }
        if parent.hasUpperBound {
            filterParameters.append("--max-parents=\(parent.maxParents)")
        }
    }

    private static func appendRevisionsAndPaths(
        revisions: [String],
        paths: [String],
        to filterParameters: inout [String]
    ) {
        if !paths.isEmpty {
            filterParameters.append("--full-history")
            filterParameters.append("--simplify-merges")
        }
        if !revisions.isEmpty {
            filterParameters.append("--end-of-options")
            filterParameters.append(contentsOf: revisions)
        }
        if !paths.isEmpty {
            filterParameters.append("--")
            filterParameters.append(contentsOf: paths)
        }
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
