//
//  String+ValidFileName.swift
//  Dreamder
//
//  Created by Khan Winter on 1/13/25.
//

import Foundation

nonisolated extension CharacterSet {
    /// On macOS, valid file names must not contain the `NULL` or `:` characters.
    static let invalidFileNameCharacters: CharacterSet = CharacterSet(charactersIn: "\0:")
}

nonisolated extension String {
    /// On macOS, valid file names must not contain the `NULL` or `:` characters, must be non-empty, and must be less
    /// than 256 UTF16 characters.
    var isValidFilename: Bool {
        !isEmpty && CharacterSet(charactersIn: self).isDisjoint(with: .invalidFileNameCharacters) && utf16.count < 256
    }
}
