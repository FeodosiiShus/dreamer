//
//  GitClient+Remote.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/17/23.
//

import Foundation

nonisolated extension GitClient {
    /// Gets all remotes
    /// - Parameter name: Name for remote
    /// - Parameter location: URL string for remote location
    func getRemotes() async throws -> [GitRemote] {
        let output = try await run(arguments: ["remote", "-v"])
        let remotes = parseGitRemotes(from: output)

        return remotes
    }

    /// Add existing remote to local git
    /// - Parameter name: Name for remote
    /// - Parameter location: URL string for remote location
    func addRemote(name: String, location: String) async throws {
        _ = try await run(arguments: ["remote", "add", name, location])
    }

    /// Get the URL of the remote
    /// > Note: If a git repository has multiple remotes, by default the `origin` remote
    /// > will be used, unless there’s an upstream branch configured for the current branch.
    /// > (Reference: https://git-scm.com/docs/git-ls-remote, https://git-scm.com/docs/git-fetch)
    /// - Returns: A URL if a remote is configured, nil otherwise
    /// - Throws: `GitClientError.outputError` if the underlying git command fails unexpectedly
    func getRemoteURL() async throws -> URL? {
        do {
            let remote = try await run(arguments: ["ls-remote", "--get-url"])
            return URL(string: remote.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch GitClientError.noRemoteConfigured {
            return nil
        } catch {
            throw error
        }
    }
}

nonisolated func parseGitRemotes(from output: String) -> [GitRemote] {
    var remotes: [String: (fetch: String?, push: String?)] = [:]

    output.split(separator: "\n").forEach { line in
        guard let tabIndex = line.firstIndex(of: "\t") else { return }
        let name = String(line[line.startIndex..<tabIndex])
        let remainder = line[line.index(after: tabIndex)...]

        let type: String
        let location: String
        if remainder.hasSuffix(" (fetch)") {
            type = "fetch"
            location = String(remainder.dropLast(" (fetch)".count))
        } else if remainder.hasSuffix(" (push)") {
            type = "push"
            location = String(remainder.dropLast(" (push)".count))
        } else {
            return
        }

        if var remote = remotes[name] {
            if type == "fetch" {
                remote.fetch = location
            } else {
                remote.push = location
            }
            remotes[name] = remote
        } else {
            if type == "fetch" {
                remotes[name] = (fetch: location, push: nil)
            } else {
                remotes[name] = (fetch: nil, push: location)
            }
        }
    }

    return remotes.compactMap { name, locations in
        if let fetchLocation = locations.fetch, let pushLocation = locations.push {
            return GitRemote(name: name, pushLocation: pushLocation, fetchLocation: fetchLocation)
        }
        return nil
    }
}
