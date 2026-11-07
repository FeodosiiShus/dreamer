//
//  GitLabAvatarURL.swift
//  DreamderModules/GitAccounts
//
//  Created by Nanashi Li on 2022/03/31.
//

import Foundation

nonisolated struct GitLabAvatarURL: Codable, Sendable {
    var url: URL?

    init(_ json: [String: AnyObject]) {
        if let urlString = json["url"] as? String, let urlFromString = URL(string: urlString) {
            url = urlFromString
        }
    }
}
