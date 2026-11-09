//
//  GitClient+Push.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation

nonisolated extension GitClient {
    /// Push changes to remote
    func pushToRemote(
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool? = false,
        force: Bool? = false,
        tags: Bool? = false
    ) async throws {
        var arguments = ["push"]
        if let remote, let branch {
            try Self.requireRefNames(remote, branch)
            if setUpstream == true {
                arguments.append("--set-upstream")
            }
            if force == true {
                arguments.append("--force")
            }
            if tags == true {
                arguments.append("--tags")
            }
            arguments += ["--end-of-options", remote, branch]
        }

        _ = try await self.run(arguments: arguments)
    }
}
