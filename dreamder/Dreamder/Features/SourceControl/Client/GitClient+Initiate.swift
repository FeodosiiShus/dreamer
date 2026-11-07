//
//  GitClient+Initiate.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/16/23.
//

import Foundation

nonisolated extension GitClient {
    /// Initiate Git repository
    func initiate() async throws {
        _ = try await run(arguments: ["init"])
    }
}
