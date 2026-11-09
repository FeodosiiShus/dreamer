import Foundation
import Testing
@testable import Dreamder

@Suite
struct CodeFileContentLoadTests {
    private static let nulReplacement = "\u{2400}"

    @Test
    func plainUtf8TextIsLoadedEditable() {
        let load = CodeFileContentLoad.classify(data: Data("let a = 1\n".utf8), fileTypeName: "public.swift-source")

        #expect(load.text == "let a = 1\n")
        #expect(load.encoding == .utf8)
        #expect(load.state == CodeFileContentState(isTooLargeForIntelligence: false, byteCount: 10))
        #expect(!load.state.isReadOnly)
        #expect(load.state.notice == nil)
    }

    @Test
    func emptyDataIsAnEmptyEditableUtf8Text() {
        let load = CodeFileContentLoad.classify(data: Data(), fileTypeName: "public.plain-text")

        #expect(load.text == "")
        #expect(load.encoding == .utf8)
        #expect(load.state == CodeFileContentState())
        #expect(load.state.notice == nil)
    }

    @Test
    func nulBytesMakeTheFileBinaryAndReadOnly() {
        let data = Data([0x61, 0x62, 0x00, 0x63, 0x64])
        let load = CodeFileContentLoad.classify(data: data, fileTypeName: "public.data")

        #expect(load.text == "ab\(Self.nulReplacement)cd")
        #expect(load.encoding == nil)
        #expect(load.state.isBinary)
        #expect(load.state.readError == nil)
        #expect(load.state.isReadOnly)
        #expect(load.state.notice == .binary)
    }

    @Test
    func previewableBinaryTypesKeepNoText() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49])

        for typeName in ["public.png", "com.adobe.pdf", "public.mpeg-4", "public.zip-archive"] {
            let load = CodeFileContentLoad.classify(data: png, fileTypeName: typeName)

            #expect(load.text == nil, "\(typeName)")
            #expect(load.state.isBinary, "\(typeName)")
            #expect(load.state.readError == nil, "\(typeName)")
        }
    }

    @Test
    func binaryDataOfUnknownTypeIsShownAsPlainText() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49])

        for typeName in ["", "not a uti", "public.data", "public.plain-text"] {
            let load = CodeFileContentLoad.classify(data: data, fileTypeName: typeName)

            #expect(load.text != nil, "\(typeName)")
            #expect(load.state.isBinary, "\(typeName)")
            #expect(load.state.isReadOnly, "\(typeName)")
        }
    }

    @Test
    func binaryPreviewIsCappedAndNulsAreReplaced() {
        var bytes = [UInt8](repeating: 0x61, count: 2 * FileSizeLimit.binaryPreview + 1)
        bytes[10] = 0x00
        let load = CodeFileContentLoad.classify(data: Data(bytes), fileTypeName: "public.data")
        let text = load.text ?? ""

        #expect(text.unicodeScalars.count == FileSizeLimit.binaryPreview)
        #expect(!text.unicodeScalars.contains("\u{0}"))
        #expect(text.unicodeScalars.contains("\u{2400}"))
        #expect(load.state.isBinary)
        #expect(!load.state.isTooLargeForIntelligence)
    }

    @Test
    func invalidTextWithoutNulIsAReadError() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9, 0x21])
        let load = CodeFileContentLoad.classify(data: latin1, fileTypeName: "public.plain-text")

        #expect(load.text == nil)
        #expect(load.encoding == nil)
        #expect(load.state.readError == .undecodable)
        #expect(!load.state.isBinary)
        #expect(load.state.isReadOnly)
        #expect(load.state.notice == .readError(.undecodable))
    }

    @Test
    func filesAtTheTenMegabyteLimitAreFlaggedReadOnly() {
        let data = Data(repeating: 0x61, count: FileSizeLimit.intelligence)
        let load = CodeFileContentLoad.classify(data: data, fileTypeName: "public.plain-text")

        #expect(load.state.isTooLargeForIntelligence)
        #expect(load.state.isReadOnly)
        #expect(load.state.byteCount == FileSizeLimit.intelligence)
        #expect(load.state.notice == .tooLarge(byteCount: FileSizeLimit.intelligence))
        #expect(load.text?.utf8.count == FileSizeLimit.intelligence)
        #expect(load.encoding == .utf8)
    }

    @Test
    func filesJustBelowTheLimitStayEditable() {
        let data = Data(repeating: 0x61, count: FileSizeLimit.intelligence - 1)
        let load = CodeFileContentLoad.classify(data: data, fileTypeName: "public.plain-text")

        #expect(!load.state.isTooLargeForIntelligence)
        #expect(!load.state.isReadOnly)
        #expect(load.state.notice == nil)
    }

    @Test
    func sizeLimitBoundaries() {
        #expect(!FileSizeLimit.exceedsIntelligenceLimit(byteCount: FileSizeLimit.intelligence - 1))
        #expect(FileSizeLimit.exceedsIntelligenceLimit(byteCount: FileSizeLimit.intelligence))
        #expect(FileSizeLimit.exceedsIntelligenceLimit(byteCount: FileSizeLimit.intelligence + 1))
        #expect(FileSizeLimit.intelligence == 10 * 1024 * 1024)
    }

    @Test
    func noticePriorityIsErrorThenBinaryThenSize() {
        var state = CodeFileContentState(isBinary: true, isTooLargeForIntelligence: true, byteCount: 5)

        #expect(state.notice == .binary)
        state.readError = .undecodable
        #expect(state.notice == .readError(.undecodable))
        state.readError = nil
        state.isBinary = false
        #expect(state.notice == .tooLarge(byteCount: 5))
        state.isTooLargeForIntelligence = false
        #expect(state.notice == nil)
        #expect(!state.isReadOnly)
    }

    @Test
    func noticeMessagesDescribeTheState() {
        let size = ByteCountFormatter.string(fromByteCount: 20_000_000, countStyle: .file)

        #expect(CodeFileNotice.tooLarge(byteCount: 20_000_000).message.contains(size))
        #expect(CodeFileNotice.tooLarge(byteCount: 20_000_000).message.contains("read-only"))
        #expect(CodeFileNotice.binary.message.contains("binary"))
        #expect(CodeFileNotice.readError(.undecodable).message.contains(CodeFileReadError.undecodable.title))
        #expect(CodeFileNotice.readError(.undecodable).message.contains(CodeFileReadError.undecodable.detail))
        #expect(!CodeFileReadError.undecodable.title.isEmpty)
        #expect(!CodeFileReadError.undecodable.detail.isEmpty)
    }
}
