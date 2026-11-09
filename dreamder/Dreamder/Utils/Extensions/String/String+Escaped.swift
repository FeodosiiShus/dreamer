//
//  String+escapedWhiteSpaces.swift
//  Dreamder
//
//  Created by Paul Ebose on 2024/07/05.
//

import Foundation

nonisolated extension String {
    private static let shellPlainScalars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.:/@+,"
    )

    func shellQuoted() -> String {
        guard !isEmpty, unicodeScalars.allSatisfy(Self.shellPlainScalars.contains) else {
            return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return self
    }

    /// Returns a new string, replacing all occurrences of ` ` with `\ ` if they aren't already escaped.
    func escapedWhiteSpaces() -> String {
        escape(replacing: " ")
    }

    /// Returns a new string, replacing all occurrences of `"` with `\"` if they aren't already escaped.
    func escapedQuotes() -> String {
        escape(replacing: #"""#)
    }

    func escape(replacing: Character) -> String {
        var string = ""
        var lastChar: Character?

        for char in self {
            defer {
                lastChar = char
            }

            guard char == replacing else {
                string.append(char)
                continue
            }

            if let lastChar, lastChar == #"\"# {
                string.append(char)
                continue
            }

            string.append(#"\"#)
            string.append(char)
        }

        return string
    }
}
