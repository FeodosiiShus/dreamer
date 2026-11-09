import Foundation
import UniformTypeIdentifiers

nonisolated enum CodeFileReadError: Equatable, Sendable {
    case undecodable

    var title: String {
        switch self {
        case .undecodable:
            return "Cannot display this file"
        }
    }

    var detail: String {
        switch self {
        case .undecodable:
            return "The file is not valid UTF-8 or UTF-16 text, so it cannot be shown or edited."
        }
    }
}

nonisolated enum CodeFileNotice: Equatable, Sendable {
    case tooLarge(byteCount: Int)
    case binary
    case readError(CodeFileReadError)

    var message: String {
        switch self {
        case .tooLarge(let byteCount):
            let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            return "The file is \(size). Highlighting and language features are disabled and the file is read-only."
        case .binary:
            return "This is a binary file. It is shown as plain text and is read-only."
        case .readError(let error):
            return "\(error.title). \(error.detail)"
        }
    }
}

nonisolated enum FileSizeLimit {
    static let intelligence = 10 * 1024 * 1024
    static let binaryPreview = 1024 * 1024
    static let synchronousOpen = 1024 * 1024

    static func exceedsIntelligenceLimit(byteCount: Int) -> Bool {
        byteCount >= intelligence
    }
}

nonisolated struct CodeFileContentState: Equatable, Sendable {
    var isBinary = false
    var isTooLargeForIntelligence = false
    var byteCount = 0
    var readError: CodeFileReadError?

    var isReadOnly: Bool {
        isBinary || isTooLargeForIntelligence || readError != nil
    }

    var notice: CodeFileNotice? {
        if let readError {
            return .readError(readError)
        }
        if isBinary {
            return .binary
        }
        if isTooLargeForIntelligence {
            return .tooLarge(byteCount: byteCount)
        }
        return nil
    }
}

nonisolated struct CodeFileContentLoad: Sendable {
    var text: String?
    var encoding: FileEncoding?
    var state: CodeFileContentState

    private static let previewableTypes: [UTType] = [.image, .pdf, .audiovisualContent, .archive]
    private static let nulReplacement = "\u{2400}"

    static func classify(data: Data, fileTypeName: String) -> CodeFileContentLoad {
        guard !data.isEmpty else {
            return CodeFileContentLoad(text: "", encoding: .utf8, state: CodeFileContentState())
        }
        var state = CodeFileContentState(
            isTooLargeForIntelligence: FileSizeLimit.exceedsIntelligenceLimit(byteCount: data.count),
            byteCount: data.count
        )
        var convertedString: NSString?
        let rawEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .allowLossyKey: false,
                .suggestedEncodingsKey: FileEncoding.allCases.map { $0.nsValue },
                .useOnlySuggestedEncodingsKey: true
            ],
            convertedString: &convertedString,
            usedLossyConversion: nil
        )
        let hasNul = data.contains(0)
        if let encoding = FileEncoding(rawEncoding), let convertedString, !(encoding == .utf8 && hasNul) {
            return CodeFileContentLoad(text: convertedString as String, encoding: encoding, state: state)
        }
        guard hasNul else {
            state.readError = .undecodable
            return CodeFileContentLoad(text: nil, encoding: nil, state: state)
        }
        state.isBinary = true
        if isPreviewableNonText(fileTypeName) {
            return CodeFileContentLoad(text: nil, encoding: nil, state: state)
        }
        return CodeFileContentLoad(text: binaryPreview(of: data), encoding: nil, state: state)
    }

    private static func isPreviewableNonText(_ fileTypeName: String) -> Bool {
        guard let type = UTType(fileTypeName) else { return false }
        return previewableTypes.contains { type.conforms(to: $0) }
    }

    private static func binaryPreview(of data: Data) -> String {
        String(decoding: data.prefix(FileSizeLimit.binaryPreview), as: UTF8.self)
            .replacingOccurrences(of: "\u{0}", with: nulReplacement)
    }
}
