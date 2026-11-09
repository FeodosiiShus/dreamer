import Foundation
@testable import Dreamder

nonisolated struct SelectionRangeFixtureMarkup {
    let text: String
    let selection: NSRange?
    let caret: Int?

    init(_ marked: String) {
        var output = ""
        var selectionStart: Int?
        var selectionEnd: Int?
        var caret: Int?
        var rest = Substring(marked)
        while !rest.isEmpty {
            if rest.hasPrefix("<selection>") {
                selectionStart = output.utf16.count
                rest.removeFirst("<selection>".count)
            } else if rest.hasPrefix("</selection>") {
                selectionEnd = output.utf16.count
                rest.removeFirst("</selection>".count)
            } else if rest.hasPrefix("<caret>") {
                caret = output.utf16.count
                rest.removeFirst("<caret>".count)
            } else {
                output.append(rest.removeFirst())
            }
        }
        text = output
        self.caret = caret
        if let selectionStart, let selectionEnd {
            selection = NSRange(location: selectionStart, length: selectionEnd - selectionStart)
        } else {
            selection = nil
        }
    }

    static func intelliJ(_ relativePath: String) throws -> SelectionRangeFixtureMarkup {
        SelectionRangeFixtureMarkup(try IntelliJTestData.text("platform/platform-tests/testData/codeInsight/\(relativePath)"))
    }

    static func afterFiles(in directory: String, suffix: String = "") throws -> [SelectionRangeFixtureMarkup] {
        var result: [SelectionRangeFixtureMarkup] = []
        var index = 1
        while FileManager.default.fileExists(
            atPath: IntelliJTestData.url("platform/platform-tests/testData/codeInsight/\(directory)/after\(index)\(suffix)")
                .path(percentEncoded: false)
        ) {
            result.append(try intelliJ("\(directory)/after\(index)\(suffix)"))
            index += 1
        }
        return result
    }
}
