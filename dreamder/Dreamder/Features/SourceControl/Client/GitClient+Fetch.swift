//
//  GitClient+Fetch.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/18/23.
//

import Foundation

nonisolated extension GitClient {
    /// Fetch changes to remote
    func fetchFromRemote() async throws {
        _ = try await self.run(arguments: ["fetch"])
    }
}
