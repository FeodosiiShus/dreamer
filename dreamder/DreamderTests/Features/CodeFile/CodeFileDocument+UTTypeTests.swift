//
//  CodeFileDocument+UTTypeTests.swift
//  DreamderTests
//
//  Created by Axel Martinez on 23/6/24.
//

import AppKit
import Testing
import UniformTypeIdentifiers

@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct UTTypeTests {
    @Test
    func textFileByContent() {
        let document = CodeFileDocument()
        document.content = NSTextStorage(string: "Some text content")
        #expect(document.utType == .text)
    }

    @Test(arguments: [
        ("public.json", UTType.json),
        ("public.python-script", UTType.pythonScript),
        ("com.adobe.pdf", UTType.pdf),
        ("public.image", UTType.image),
        ("public.png", UTType.png),
        ("public.audio", UTType.audio),
        ("public.mp3", UTType.mp3),
        ("public.video", UTType.video),
        ("public.mpeg-4", UTType.mpeg4Movie)
    ])
    func fileTypeDeterminesTheUTType(fileType: String, expected: UTType) {
        let document = CodeFileDocument()
        document.fileType = fileType
        #expect(document.utType == expected)
    }

    @Test
    func unknownFileTypeHasNoUTType() {
        let document = CodeFileDocument()
        document.fileType = "unknown"
        #expect(document.utType == nil)
    }

    @Test
    func emptyFileTypeAndContentHaveNoUTType() {
        #expect(CodeFileDocument().utType == nil)
    }
}
