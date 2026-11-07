//
//  SemanticTokenRange.swift
//  Dreamder
//
//  Created by Khan Winter on 12/26/24.
//

/// Represents the range of a semantic token.
nonisolated struct SemanticTokenRange: Sendable {
    let line: UInt32
    let char: UInt32
    let length: UInt32
}
