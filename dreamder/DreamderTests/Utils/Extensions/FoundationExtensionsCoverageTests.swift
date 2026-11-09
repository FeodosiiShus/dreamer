import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BundleInfoExtensionTests {
    private func mainValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private func makeBundle(in directory: URL, info: [String: String]) throws -> Bundle {
        let contents = directory.appending(path: "Fixture.bundle/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return try #require(Bundle(url: contents.deletingLastPathComponent()))
    }

    @Test
    func displayNamePrefersDisplayNameThenBundleNameThenFallback() throws {
        try withTempDir { directory in
            let both = try makeBundle(in: directory, info: ["CFBundleDisplayName": "Shown", "CFBundleName": "Named"])
            #expect(both.applicationDisplayName == "Shown")
        }
        try withTempDir { directory in
            let named = try makeBundle(in: directory, info: ["CFBundleName": "Named"])
            #expect(named.applicationDisplayName == "Named")
        }
        try withTempDir { directory in
            let anonymous = try makeBundle(in: directory, info: ["CFBundleIdentifier": "dev.dreamder.fixture"])
            #expect(anonymous.applicationDisplayName == "Unknown App")
        }
    }

    @Test
    func staticDisplayNameReadsTheMainBundle() {
        #expect(Bundle.displayName == Bundle.main.applicationDisplayName)
    }

    @Test
    func optionalInfoKeysMirrorTheMainBundle() {
        #expect(Bundle.copyrightString == mainValue("NSHumanReadableCopyright"))
        #expect(Bundle.versionString == mainValue("CFBundleShortVersionString"))
        #expect(Bundle.buildString == mainValue("CFBundleVersion"))
        #expect(Bundle.versionPostfix == mainValue("CE_VERSION_POSTFIX"))
    }
}

@MainActor
@Suite(.uiGate)
struct DateFormattedExtensionTests {
    private func makeDate(hour: Int = 12, minute: Int = 0, second: Int = 0) throws -> Date {
        let components = DateComponents(year: 2001, month: 2, day: 3, hour: hour, minute: minute, second: second)
        return try #require(Calendar.current.date(from: components))
    }

    @Test
    func olderDatesUseTheShortLocalizedDateWithoutTime() throws {
        let date = try makeDate()

        #expect(date.relativeStringToNow(locale: Locale(identifier: "en_US")) == "2/3/01")
        #expect(date.relativeStringToNow(locale: Locale(identifier: "de_DE")) == "03.02.01")
    }

    @Test
    func todayUsesTheRelativeStyleInsteadOfTheShortDate() {
        let result = Date.now.relativeStringToNow(locale: Locale(identifier: "en_US"))

        #expect(!result.isEmpty)
        #expect(!result.contains("/"))
    }
}

@MainActor
@Suite(.uiGate)
struct FileManagerMakeExecutableTests {
    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    @Test
    func addsOnlyTheOwnerExecuteBit() throws {
        let directory = try makeTemporaryDirectory(label: "makeExecutable")
        defer { removeTemporaryDirectory(directory) }
        let file = directory.appending(path: "tool.sh", directoryHint: .notDirectory)
        try Data("#!/bin/sh\n".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: file.path(percentEncoded: false)
        )

        try FileManager.default.makeExecutable(file)

        #expect(try permissions(of: file) == 0o744)
        #expect(FileManager.default.isExecutableFile(atPath: file.path(percentEncoded: false)))
    }

    @Test
    func keepsAnAlreadyExecutableFileUnchanged() throws {
        let directory = try makeTemporaryDirectory(label: "makeExecutableTwice")
        defer { removeTemporaryDirectory(directory) }
        let file = directory.appending(path: "tool", directoryHint: .notDirectory)
        try Data().write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: file.path(percentEncoded: false)
        )

        try FileManager.default.makeExecutable(file)

        #expect(try permissions(of: file) == 0o755)
    }

    @Test
    func missingFilesThrow() throws {
        let directory = try makeTemporaryDirectory(label: "makeExecutableMissing")
        defer { removeTemporaryDirectory(directory) }
        let missing = directory.appending(path: "missing", directoryHint: .notDirectory)

        #expect(throws: (any Error).self) {
            try FileManager.default.makeExecutable(missing)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct HexStringInitializerTests {
    @Test
    func unsignedParsesWithAndWithoutPrefix() {
        #expect(UInt(hexString: "0x1F") == 31)
        #expect(UInt(hexString: "1f") == 31)
        #expect(UInt(hexString: "ff") == 255)
    }

    @Test
    func unsignedRejectsInvalidInput() {
        #expect(UInt(hexString: "zz") == nil)
        #expect(UInt(hexString: "") == nil)
        #expect(UInt(hexString: "0x") == nil)
        #expect(UInt(hexString: "-1") == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct OperatingSystemVersionStringTests {
    @Test
    func semverStringJoinsMajorMinorAndPatch() {
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 3)
        #expect(version.semverString == "26.1.3")
        #expect(OperatingSystemVersion(majorVersion: 0, minorVersion: 0, patchVersion: 0).semverString == "0.0.0")
    }

    @Test
    func semverStringMatchesTheRunningSystem() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(version.semverString == "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }
}
