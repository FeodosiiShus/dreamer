//
//  GitStashEntry.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/20/23.
//

import Foundation

nonisolated struct GitStashEntry: Hashable, Sendable {
    let index: Int
    let message: String
    let date: Date
}
