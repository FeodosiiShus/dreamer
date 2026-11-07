//
//  SemanticToken+Position.swift
//  Dreamder
//
//  Created by Khan Winter on 12/26/24.
//

import LanguageServerProtocol

nonisolated extension SemanticToken {
    var startPosition: Position {
        Position(line: Int(line), character: Int(char))
    }

    var endPosition: Position {
        Position(line: Int(line), character: Int(char + length))
    }
}
