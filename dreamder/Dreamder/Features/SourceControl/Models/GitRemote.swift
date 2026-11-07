//
//  GitRemote.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/17/23.
//

import Foundation

nonisolated struct GitRemote: Hashable, Sendable {
    let name: String
    let pushLocation: String
    let fetchLocation: String
    var branches: [GitBranch] = []
}
