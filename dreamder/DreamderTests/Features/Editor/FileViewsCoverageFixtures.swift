import AppKit
import CoreGraphics
import Foundation
@testable import Dreamder

struct FileViewsCoverageFixtureError: Error {}

@MainActor
enum FileViewsCoverageFixtures {
    static let pngType = "public.png"
    static let jpegType = "public.jpeg"
    static let pdfType = "com.adobe.pdf"
    static let dataType = "public.data"
    static let textType = "public.plain-text"

    static func writePNG(to url: URL, width: Int = 64, height: Int = 48) throws {
        let data = try bitmap(width: width, height: height).representation(using: .png, properties: [:])
        try write(data, to: url)
    }

    static func writeJPEG(to url: URL, width: Int = 64, height: Int = 48) throws {
        let data = try bitmap(width: width, height: height)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        try write(data, to: url)
    }

    static func writePDF(to url: URL, pages: Int = 1) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw FileViewsCoverageFixtureError()
        }
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(box)
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func writeBlob(to url: URL) throws {
        let bytes = (0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        try Data(bytes).write(to: url)
    }

    static func writeGarbage(to url: URL) throws {
        try "this is not a valid file of its extension".write(to: url, atomically: true, encoding: .utf8)
    }

    static func nonTextDocument(at url: URL, type: String) throws -> CodeFileDocument {
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: type)
        document.fileType = type
        document.content = nil
        return document
    }

    static func textDocument(at url: URL, contents: String, type: String = textType) throws -> CodeFileDocument {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: type)
    }

    static func fileSize(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int else { throw FileViewsCoverageFixtureError() }
        return size
    }

    private static func bitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let pixels = representation.bitmapData else {
            throw FileViewsCoverageFixtureError()
        }
        pixels.initialize(repeating: 180, count: representation.bytesPerRow * height)
        return representation
    }

    private static func write(_ data: Data?, to url: URL) throws {
        guard let data else { throw FileViewsCoverageFixtureError() }
        try data.write(to: url)
    }
}
