//
//  UnitTests.swift
//  DreamderModules/DreamderUtilsTests
//
//  Created by Lukas Pistrol on 01.05.22.
//

import Foundation
import SwiftUI
import XCTest
@testable import Dreamder

final class DreamderUtilsExtensionsUnitTests: XCTestCase {

    // MARK: - COLOR + HEX

    func testColorConversionFromHEXString() throws {
        let colorString = "#123456"
        let color = Color(hex: colorString)

        XCTAssertEqual(colorString, color.hexString)
    }

    func testNSColorConversionFromHEXString() throws {
        let colorString = "#123456"
        let color = NSColor(hex: colorString)

        XCTAssertEqual(colorString, color.hexString)
    }

    func testColorConversionFromHEXInt() throws {
        let colorInt = 0x123456
        let color = Color(hex: colorInt)

        XCTAssertEqual(colorInt, color.hex)
    }

    func testNSColorConversionFromHEXInt() throws {
        let colorInt = 0x123456
        let color = NSColor(hex: colorInt)

        XCTAssertEqual(colorInt, color.hex)
    }

    func testColorConversionAlphaValue() throws {
        let alpha = 0.25
        let color = Color(hex: "#123456", alpha: alpha)

        XCTAssertEqual(alpha, color.alphaComponent)
    }

    func testNSColorConversionAlphaValue() throws {
        let alpha = 0.25
        let color = NSColor(hex: "#123456", alpha: alpha)

        XCTAssertEqual(alpha, color.alphaComponent)
    }

    // MARK: - DATE + FORMATTED

    func testRelativeDateStringMinutes() throws {
        let date = Date.now.addingTimeInterval(-61)
        let string = date.relativeStringToNow(locale: Locale(identifier: "en_US"))

        XCTAssertEqual("1 min. ago", string)
    }

    func testRelativeDateStringHours() throws {
        let date = Date.now.addingTimeInterval(-3_601)
        let string = date.relativeStringToNow(locale: Locale(identifier: "en_US"))

        XCTAssertEqual("1 hr. ago", string)
    }

    func testRelativeDateStringDays() throws {
        let date = Date.now.addingTimeInterval(-86_400)
        let string = date.relativeStringToNow(locale: Locale(identifier: "en_US"))

        XCTAssertEqual("yesterday", string)
    }

    // MARK: - STRING + MD5

    func testMD5GenerationCaseSensitive() throws {
        let testString = "Dreamder"
        let md5 = testString.md5(caseSensitive: true)

        let result = "18b61aee129e66a03b7f2c3b0199c91c"
        XCTAssertEqual(result, md5)
    }

    func testMD5Generation() throws {
        let testString = "Dreamder"
        let md5 = testString.md5(caseSensitive: false)

        let result = "6a8aa5e073948c6f053270bc0c1a0a8e"
        XCTAssertEqual(result, md5)
    }

    // MARK: - STRING + SHA256

    func testSHA256GenerationCaseSensitive() throws {
        let testString = "Dreamder"
        let md5 = testString.sha256(caseSensitive: true)

        let result = "70e9b4359c68bce6824c2d59bd12da6af1eefee3c5af4617eea44e0ebc509896"
        XCTAssertEqual(result, md5)
    }

    func test256Generation() throws {
        let testString = "Dreamder"
        let md5 = testString.sha256(caseSensitive: false)

        let result = "71e84ea7cd261ebd0c8c3ca732b1e42f6ef5bf0b8098d6d2b3a769b3d15f5f1d"
        XCTAssertEqual(result, md5)
    }

    // MARK: - STRING + REMOVING OCCURRENCES

    func testRemovingNewLines() throws {
        let string = "Hello, \nWorld!"
        let withoutNewLines = string.removingNewLines()

        let result = "Hello, World!"
        XCTAssertEqual(result, withoutNewLines)
    }

    func testRemovingSpaces() throws {
        let string = "Hello, World!"
        let withoutSpaces = string.removingSpaces()

        let result = "Hello,World!"
        XCTAssertEqual(result, withoutSpaces)
    }

    // MARK: - STRING + VALID FILE NAME

    func testValidFileName() {
        let validCases = [
            "hello world",
            "newSwiftFile.swift",
            "documento_español.txt",
            "dokument_deutsch.pdf",
            "rapport_français.docx",
            "レポート_日本語.xlsx",
            "отчет_русский.pptx",
            "보고서_한국어.txt",
            "文件_中文.pdf",
            "dokument_svenska.txt",
            "relatório_português.docx",
            "relazione_italiano.pdf",
            "file_with_emoji_😊.txt",
            "emoji_report_📄.pdf",
            "archivo_con_emoji_🌟.docx",
            "文件和表情符号_🚀.txt",
            "rapport_avec_emoji_🎨.pptx",
            // 255 characters (exactly the maximum)
            String(repeating: "abcd", count: 63) + "abc"
        ]

        for validCase in validCases {
            XCTAssertTrue(validCase.isValidFilename, "Detected invalid case \"\(validCase)\", should be valid.")
        }
    }

    func testInvalidFileName() {
        // The only limitations for macOS file extensions is no ':' and no NULL characters and 255 UTF16 char limit.
        let invalidCases = [
            "",
            ":",
            "\0",
            "Hell\0 World!",
            "export:2024-04-12.txt",
            // 256 characters (1 too long)
            String(repeating: "abcd", count: 64)
        ]

        for invalidCase in invalidCases {
            XCTAssertFalse(invalidCase.isValidFilename, "Detected valid case \"\(invalidCase)\", should be invalid.")
        }
    }

    // MARK: - STRING + ESCAPED

    func testEscapeQuotes() {
        let string = #"this/is/"a path/Hello "world"#
        XCTAssertEqual(string.escapedQuotes(), #"this/is/\"a path/Hello \"world"#)
    }

    func testEscapeQuotesForAlreadyEscapedString() {
        let string = #"this/is/"a path/Hello \"world"#
        XCTAssertEqual(string.escapedQuotes(), #"this/is/\"a path/Hello \"world"#)
    }

    // MARK: - URL + Contains

    func testURLContainsSubPath() {
        XCTAssertTrue(URL(filePath: "/Users/Bob/Desktop").containsSubPath(URL(filePath: "/Users/Bob/Desktop/file.txt")))
        XCTAssertFalse(URL(filePath: "/Users/Bob/Desktop").containsSubPath(URL(filePath: "/Users/Bob/Desktop/")))
        XCTAssertFalse(URL(filePath: "/Users/Bob/Desktop").containsSubPath(URL(filePath: "/Users/Bob/")))
        XCTAssertTrue(URL(filePath: "/Users/Bob/Desktop").containsSubPath(URL(filePath: "/Users/Bob/Desktop/Folder")))
    }

    func testURLSharedComponentsCount() {
        // URL Treats the leading `/` as a component, so these all appear to have + 1 but are correct.
        XCTAssertEqual(
            URL(filePath: "/Users/Bob/Desktop").sharedComponents(URL(filePath: "/Users/Bob/Desktop/file.txt")),
            4
        )
        XCTAssertEqual(
            URL(filePath: "/Users/Bob/Desktop").sharedComponents(URL(filePath: "/Users/Bob/Desktop/")),
            4
        )
        XCTAssertEqual(
            URL(filePath: "/Users/Bob/Desktop").sharedComponents(URL(filePath: "/Users/Bob/")),
            3
        )
        XCTAssertEqual(
            URL(filePath: "/Users/Bob/Desktop").sharedComponents(URL(filePath: "/Users/Bob/Desktop/Folder")),
            4
        )

        XCTAssertEqual(
            URL(filePath: "/Users/Bob/Desktop").sharedComponents(URL(filePath: "/Some Other/ Path ")),
            1
        )
    }
}
