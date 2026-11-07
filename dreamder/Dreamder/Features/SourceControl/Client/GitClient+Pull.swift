//
//  GitClient+Pull.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/18/23.
//

import Foundation

nonisolated extension GitClient {
    /// Pull changes from remote
    func pullFromRemote(remote: String? = nil, branch: String? = nil, rebase: Bool = false) async throws {
        var arguments = ["pull", rebase ? "--rebase" : "--no-rebase"]

        if let remote = remote, let branch = branch {
            arguments += [remote, branch]
        }

        _ = try await self.run(arguments: arguments)
    }
}
