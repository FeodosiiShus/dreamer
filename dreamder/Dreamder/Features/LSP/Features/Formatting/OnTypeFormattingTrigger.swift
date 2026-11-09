import Foundation
import LanguageServerProtocol

nonisolated enum OnTypeFormattingTrigger {
    static func character(inserted string: String, options: DocumentOnTypeFormattingOptions) -> String? {
        guard string.unicodeScalars.count == 1 else { return nil }
        let triggers = [options.firstTriggerCharacter] + (options.moreTriggerCharacter ?? [])
        return triggers.contains(string) ? string : nil
    }

    static func caretOffset(afterInserting string: String, replacing range: NSRange) -> Int {
        range.location + string.utf16.count
    }

    static func isTyped(caretOffset: Int, selections: [NSRange]) -> Bool {
        selections == [NSRange(location: caretOffset, length: 0)]
    }
}
