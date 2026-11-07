import Foundation

nonisolated extension GitClient {
    static let logGraphFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%D%x1f%s%x1f%B"
    static let logGraphDefaultLimit = 2000

    @concurrent
    func logGraph(
        filters: GitLogFilterCollection = GitLogFilterCollection(),
        options: GitLogOptions = GitLogOptions(),
        userResolver: GitLogUserResolver = GitLogUserResolver(),
        limit: Int = GitClient.logGraphDefaultLimit
    ) async throws -> [GitLogCommit] {
        let hasBranchLikeFilter = filters.branch != nil || filters.revision != nil || filters.range != nil
        var existingBranches: [String] = []
        if filters.branch != nil {
            existingBranches = try await logGraphBranchNames()
        }
        var headIsResolvable = true
        if !hasBranchLikeFilter {
            headIsResolvable = await logGraphHeadIsResolvable()
        }
        guard let parameters = GitLogArguments.parameters(
            filters: filters,
            options: options,
            maxCount: limit,
            existingBranches: existingBranches,
            userResolver: userResolver,
            headIsResolvable: headIsResolvable
        ) else {
            return []
        }
        let arguments = GitLogArguments.arguments(parameters: parameters, format: Self.logGraphFormat)
        return Self.logGraphParse(try await run(arguments: arguments))
    }

    func logGraphBranchNames() async throws -> [String] {
        let output = try await run(arguments: ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"])
        return Self.logGraphBranchNames(fromRefNames: output)
    }

    static func logGraphBranchNames(fromRefNames output: String) -> [String] {
        var names: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let ref = line.trimmingCharacters(in: .whitespaces)
            let name: String
            if ref.hasPrefix("refs/heads/") {
                name = String(ref.dropFirst("refs/heads/".count))
            } else if ref.hasPrefix("refs/remotes/") {
                name = String(ref.dropFirst("refs/remotes/".count))
            } else {
                continue
            }
            guard !name.isEmpty, name != "HEAD", !name.hasSuffix("/HEAD") else { continue }
            names.append(name)
        }
        return names
    }

    func logGraphHeadIsResolvable() async -> Bool {
        guard let result = try? await runResult(arguments: ["rev-parse", "--verify", "--quiet", "HEAD"]) else {
            return false
        }
        return result.success
    }

    func logGraphCurrentUser() async -> GitLogUser? {
        let name: String? = try? await getConfig(key: "user.name")
        let email: String? = try? await getConfig(key: "user.email")
        guard name != nil || email != nil else { return nil }
        return GitLogUser(name: name ?? "", email: email ?? "")
    }

    func logGraphMessage(hash: String) async throws -> String {
        let output = try await run(arguments: ["log", "-1", "--format=%B", hash])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func logGraphChangedFiles(commit: GitLogCommit) async throws -> [GitChangedFile] {
        let output: String
        if let firstParent = commit.parents.first {
            output = try await run(arguments: ["diff", "--name-status", firstParent, commit.hash])
        } else {
            output = try await run(arguments: ["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", commit.hash])
        }
        return Self.logGraphParseChangedFiles(output, root: directoryURL)
    }

    static func logGraphParseChangedFiles(_ output: String, root: URL) -> [GitChangedFile] {
        output.components(separatedBy: "\n").compactMap { line -> GitChangedFile? in
            let fields = line.split(separator: "\t")
            guard fields.count >= 2,
                  let status = fields.first.flatMap({ GitStatus(rawValue: String($0.prefix(1))) }) else {
                return nil
            }
            let path = String(fields[fields.count - 1])
            guard !path.isEmpty else { return nil }
            return GitChangedFile(
                status: status,
                stagedStatus: .none,
                fileURL: root.appending(path: path),
                originalFilename: fields.count == 3 ? String(fields[1]) : nil
            )
        }
    }

    static func logGraphParse(_ output: String) -> [GitLogCommit] {
        output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .compactMap { logGraphParse(record: String($0)) }
    }

    static func logGraphParse(record: String) -> GitLogCommit? {
        let record = record.trimmingCharacters(in: .newlines)
        let fields = record.split(separator: "\u{1f}", maxSplits: 8, omittingEmptySubsequences: false)
        guard fields.count == 9, let authorSeconds = TimeInterval(fields[4]) else {
            return nil
        }
        let hash = String(fields[0])
        guard !hash.isEmpty else { return nil }
        let commitSeconds = TimeInterval(fields[5]) ?? authorSeconds
        let subject = String(fields[7])
        let message = String(fields[8]).trimmingCharacters(in: .whitespacesAndNewlines)
        return GitLogCommit(
            hash: hash,
            parents: fields[1].split(separator: " ").map { String($0) },
            authorName: String(fields[2]),
            authorEmail: String(fields[3]),
            date: Date(timeIntervalSince1970: authorSeconds),
            commitDate: Date(timeIntervalSince1970: commitSeconds),
            refs: logGraphRefs(from: String(fields[6])),
            subject: subject,
            message: message.isEmpty ? subject : message
        )
    }

    static func logGraphRefs(from decoration: String) -> [GitLogRef] {
        let trimmed = decoration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var refs: [GitLogRef] = []
        var seen = Set<String>()

        for entry in trimmed.split(separator: ",") {
            var name = String(entry).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "grafted", !name.hasSuffix("/HEAD") else { continue }

            let kind: GitLogRef.Kind
            if let arrow = name.range(of: "->") {
                let source = String(name[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard source == "HEAD" else { continue }
                name = String(name[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
                kind = .head
            } else if name.hasPrefix("tag: ") {
                name = String(name.dropFirst("tag: ".count)).trimmingCharacters(in: .whitespaces)
                kind = .tag
            } else if name.contains("/") {
                kind = .remote
            } else {
                kind = .branch
            }

            guard !name.isEmpty, seen.insert("\(kind.rawValue):\(name)").inserted else { continue }
            refs.append(GitLogRef(name: name, kind: kind))
        }

        return refs
    }

    static func logGraphQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
