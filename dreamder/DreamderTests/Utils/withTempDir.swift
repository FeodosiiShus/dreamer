//
//  withTempDir.swift
//  DreamderTests
//
//  Created by Khan Winter on 7/3/25.
//

import Foundation
import Testing
import XCTest

func withTempDir(_ test: (URL) async throws -> Void) async throws {
    let tempDirURL = try makeTemporaryDirectory(label: currentSwiftTestingLabel())
    defer { removeTemporaryDirectory(tempDirURL) }
    try await test(tempDirURL)
}

func withTempDir(_ test: (URL) throws -> Void) throws {
    let tempDirURL = try makeTemporaryDirectory(label: currentSwiftTestingLabel())
    defer { removeTemporaryDirectory(tempDirURL) }
    try test(tempDirURL)
}

func makeTemporaryDirectory(label: String = "") throws -> URL {
    let sanitizedLabel = String(
        label.components(separatedBy: CharacterSet(charactersIn: "/:?%*|\"<>[]- ")).joined().prefix(80)
    )
    let tempDirURL = FileManager.default.temporaryDirectory
        .resolvingSymlinksInPath()
        .appending(path: "DreamderTestDirectory" + sanitizedLabel + UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
    return tempDirURL
}

func removeTemporaryDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    try? FileManager.default.removeItem(at: url)
}

extension XCTestCase {
    func makeTempDirectory() throws -> URL {
        let url = try makeTemporaryDirectory(label: name)
        addTeardownBlock { removeTemporaryDirectory(url) }
        return url
    }
}

private func currentSwiftTestingLabel() -> String {
    guard let currentTest = Test.current else { return "" }
    return currentTest.sourceLocation.fileID + currentTest.name
}
