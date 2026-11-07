//
//  GitClient+Validate.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/29/23.
//

import Foundation

nonisolated extension GitClient {
    /// Determines if the current directory is a valid git repository.
    ///
    /// Runs `git rev-parse --is-inside-work-tree`.
    ///
    /// - Returns: True, if git finds a valid repository.
    func validate() async -> Bool {
        guard let result = try? await runResult(arguments: ["rev-parse", "--is-inside-work-tree"]),
              result.success else {
            return false
        }
        return result.outputText.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}
