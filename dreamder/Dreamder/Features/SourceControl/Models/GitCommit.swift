//
//  GitCommit.swift
//  DreamderModules/Git
//
//  Created by Marco Carnevali on 27/03/22.
//

import Foundation.NSDate

/// Model class to help map commit history log data
nonisolated struct GitCommit: Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let hash: String
    let commitHash: String
    let message: String
    let author: String
    let authorEmail: String
    let committer: String
    let committerEmail: String
    let body: String
    let refs: [String]
    let tag: String
    let remoteURL: URL?
    let date: Date
}
