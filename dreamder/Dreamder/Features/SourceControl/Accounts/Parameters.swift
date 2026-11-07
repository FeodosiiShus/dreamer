//
//  Parameters.swift
//  DreamderModules/GitAccounts
//
//  Created by Nanashi Li on 2022/03/31.
//

import Foundation

nonisolated enum GitSortDirection: String, Sendable {
    case asc
    case desc
}

nonisolated enum GitSortType: String, Sendable {
    case created
    case updated
    case popularity
    case longRunning = "long-running"
}
