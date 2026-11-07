import AppKit

nonisolated final class CodeTextStorage: NSTextStorage {
    private let backing: NSMutableAttributedString

    override init() {
        backing = NSMutableAttributedString()
        super.init()
    }

    override init(string: String) {
        backing = NSMutableAttributedString(string: string)
        super.init()
    }

    override init(attributedString: NSAttributedString) {
        backing = NSMutableAttributedString(attributedString: attributedString)
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        nil
    }

    override var string: String {
        backing.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        guard location < backing.length else {
            range?.pointee = NSRange(location: location, length: 1)
            return [:]
        }
        return backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        guard let clamped = clamp(range) else { return }
        beginEditing()
        backing.replaceCharacters(in: clamped, with: str)
        edited(.editedCharacters, range: clamped, changeInLength: (str as NSString).length - clamped.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        guard let clamped = clamp(range), clamped.length > 0 else { return }
        beginEditing()
        backing.setAttributes(attrs, range: clamped)
        edited(.editedAttributes, range: clamped, changeInLength: 0)
        endEditing()
    }

    private func clamp(_ range: NSRange) -> NSRange? {
        let length = backing.length
        guard range.location != NSNotFound, range.location <= length else { return nil }
        let end = min(range.location + max(range.length, 0), length)
        return NSRange(location: range.location, length: end - range.location)
    }
}
