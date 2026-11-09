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
    defer { removeStandardDefaultsKeys(referencing: url) }
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    try? FileManager.default.removeItem(at: url)
}

func removeStandardDefaultsKeys(referencing directory: URL) {
    guard let domain = Bundle.main.bundleIdentifier else { return }
    removeDefaultsKeys(referencing: directory, in: .standard, domain: domain)
}

func removeDefaultsKeys(referencing directory: URL, in defaults: UserDefaults, domain: String) {
    let fragments = defaultsKeyFragments(of: directory)
    let stored = defaults.persistentDomain(forName: domain) ?? [:]
    for key in stored.keys where fragments.contains(where: { key.contains($0) }) {
        defaults.removeObject(forKey: key)
    }
}

private func defaultsKeyFragments(of directory: URL) -> [String] {
    let path = directory.standardizedFileURL.path(percentEncoded: false)
    let privatePrefix = "/private"
    let spellings: [String]
    if path.hasPrefix(privatePrefix + "/") {
        spellings = [path, String(path.dropFirst(privatePrefix.count))]
    } else {
        spellings = [path, privatePrefix + path]
    }
    let urlForms = spellings.map { URL(fileURLWithPath: $0, isDirectory: false).absoluteString }
    return spellings + urlForms
}

nonisolated enum StaleTestDefaults {
    private static let temporaryRoots = ["/private/var/folders/", "/var/folders/", "/private/tmp/", "/tmp/"]

    static func purge() {
        guard let domain = Bundle.main.bundleIdentifier,
              let stored = UserDefaults.standard.persistentDomain(forName: domain) else { return }
        for key in stored.keys {
            guard let path = referencedTemporaryPath(in: key),
                  !FileManager.default.fileExists(atPath: path) else { continue }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func referencedTemporaryPath(in key: String) -> String? {
        let decoded = key.removingPercentEncoding ?? key
        guard let start = temporaryRoots.compactMap({ decoded.range(of: $0)?.lowerBound }).min() else { return nil }
        return String(decoded[start...])
    }
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
