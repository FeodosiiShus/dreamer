import Foundation

nonisolated struct SnippetVariableContext: Sendable, Equatable {
    var selectedText = ""
    var currentLine = ""
    var currentWord = ""
    var lineIndex = 0
    var fileURL: URL?

    func value(for name: String) -> String? {
        switch name {
        case "TM_SELECTED_TEXT":
            return selectedText
        case "TM_CURRENT_LINE":
            return currentLine
        case "TM_CURRENT_WORD":
            return currentWord
        case "TM_LINE_INDEX":
            return String(lineIndex)
        case "TM_LINE_NUMBER":
            return String(lineIndex + 1)
        case "TM_FILENAME":
            return fileURL?.lastPathComponent ?? ""
        case "TM_FILENAME_BASE":
            return fileURL?.deletingPathExtension().lastPathComponent ?? ""
        case "TM_DIRECTORY":
            return fileURL?.deletingLastPathComponent().path ?? ""
        case "TM_FILEPATH":
            return fileURL?.path ?? ""
        default:
            return nil
        }
    }
}
