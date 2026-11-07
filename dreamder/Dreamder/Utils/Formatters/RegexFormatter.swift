//
//  RegexFormatter.swift
//  Dreamder
//
//  Created by Austin Condiff on 7/28/24.
//

import SwiftUI

nonisolated class RegexFormatter: Formatter {
    let regex: NSRegularExpression?
    let replacementTemplate: String

    init(pattern: String, replacementTemplate: String = "") {
        self.regex = try? NSRegularExpression(pattern: pattern, options: [])
        self.replacementTemplate = replacementTemplate
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func string(for obj: Any?) -> String? {
        guard let string = obj as? String else { return nil }
        return formatString(string)
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = formatString(string) as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let formatted = formatString(partialString)
        newEditingString?.pointee = formatted as NSString
        return formatted == partialString
    }

    private func formatString(_ string: String) -> String {
        guard let regex else { return string }
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacementTemplate)
    }
}
