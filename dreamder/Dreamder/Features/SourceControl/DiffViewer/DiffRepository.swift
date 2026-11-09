import Foundation

enum DiffContentSource: Equatable {
    case missing
    case workingTree
    case history(ref: String, path: String)
}

struct DiffFileRequest: Identifiable, Equatable {
    let path: String
    let status: GitStatus
    var originalPath: String?

    let left: DiffContentSource
    let right: DiffContentSource

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

enum DiffSideText: Equatable {
    case text(String)
    case binary
    case empty

    var stringValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }

    var isBinary: Bool { self == .binary }
}

struct DiffDocumentContent: Equatable {
    let left: DiffSideText
    let right: DiffSideText
}

enum DiffViewerMode: Equatable {
    case workingTree(ref: String)
    case commit(hash: String, parentHash: String?)
}

struct DiffRepository {
    let gitClient: GitClient
    let rootURL: URL

    init(gitClient: GitClient, rootURL: URL) {
        self.gitClient = gitClient
        self.rootURL = rootURL
    }

    init?(workspace: WorkspaceDocument) {
        guard let manager = workspace.sourceControlManager else { return nil }
        self.init(gitClient: manager.gitClient, rootURL: manager.repositoryURL)
    }

    func workingTreeRequests(against ref: String) async throws -> [DiffFileRequest] {
        let tracked = try await gitClient.run(
            "-c core.quotePath=false diff --name-status \(GitClient.logGraphQuote(ref))" + gitClient.scopePathspec
        )
        let untracked = (try? await gitClient.run(
            "-c core.quotePath=false ls-files --others --exclude-standard" + gitClient.scopePathspec
        )) ?? ""

        var requests: [DiffFileRequest] = []
        var seen = Set<String>()

        for entry in Self.parseNameStatus(tracked) {
            guard seen.insert(entry.path).inserted else { continue }
            requests.append(workingTreeRequest(
                status: entry.status,
                path: entry.path,
                originalPath: entry.originalPath,
                ref: ref
            ))
        }

        for line in untracked.split(separator: "\n", omittingEmptySubsequences: true) {
            let path = line.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            requests.append(workingTreeRequest(status: .untracked, path: path, originalPath: nil, ref: ref))
        }

        return requests.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func workingTreeRequest(status: GitStatus, path: String, originalPath: String?, ref: String) -> DiffFileRequest {
        let left: DiffContentSource
        switch status {
        case .added, .untracked:
            left = .missing
        default:
            left = .history(ref: ref, path: originalPath ?? path)
        }
        let right: DiffContentSource = status == .deleted ? .missing : .workingTree
        return DiffFileRequest(path: path, status: status, originalPath: originalPath, left: left, right: right)
    }

    func commitRequest(path: String, status: GitStatus, commit hash: String, parent parentHash: String?) -> DiffFileRequest {
        let left: DiffContentSource = parentHash.map { .history(ref: $0, path: path) } ?? .missing
        return DiffFileRequest(
            path: path,
            status: status,
            originalPath: nil,
            left: left,
            right: .history(ref: hash, path: path)
        )
    }

    func load(_ request: DiffFileRequest) async -> DiffDocumentContent {
        async let left = text(for: request.left, request: request)
        async let right = text(for: request.right, request: request)
        return await DiffDocumentContent(left: left, right: right)
    }

    private func text(for source: DiffContentSource, request: DiffFileRequest) async -> DiffSideText {
        switch source {
        case .missing:
            return .empty
        case .workingTree:
            return Self.workingTreeText(at: rootURL.appending(path: request.path))
        case let .history(ref, path):
            return await historyText(ref: ref, path: path)
        }
    }

    private static func workingTreeText(at url: URL) -> DiffSideText {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        if data.contains(0) { return .binary }
        guard let text = String(data: data, encoding: .utf8) else { return .binary }
        return .text(text)
    }

    private func historyText(ref: String, path: String) async -> DiffSideText {
        let object = "\(ref):\(path)"
        if let output = try? await gitClient.run("show \(GitClient.logGraphQuote(object))") {
            return output.contains("\0") ? .binary : .text(output)
        }
        let tree = try? await gitClient.run(
            "ls-tree --name-only \(GitClient.logGraphQuote(ref)) -- \(GitClient.logGraphQuote(path))"
        )
        return (tree?.isEmpty == false) ? .binary : .empty
    }

    static func parseNameStatus(
        _ output: String
    ) -> [(status: GitStatus, path: String, originalPath: String?)] {
        output.split(separator: "\n").compactMap { line -> (status: GitStatus, path: String, originalPath: String?)? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2,
                  let status = GitStatus(rawValue: String(fields[0].prefix(1))),
                  status != .none else {
                return nil
            }
            let path = String(fields[fields.count - 1])
            guard !path.isEmpty else { return nil }
            let originalPath = fields.count >= 3 ? String(fields[1]) : nil
            return (status: status, path: path, originalPath: originalPath)
        }
    }
}
