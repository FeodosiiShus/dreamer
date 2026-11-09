import AppKit
import AboutWindow
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class AboutMeasuredSize {
    var size = CGSize.zero
}

private let aboutCoveragePackagesJSON = """
{
  "pins": [
    {
      "identity": "zeta",
      "kind": "remoteSourceControl",
      "location": "https://github.com/example/Zeta.git",
      "state": { "revision": "abc", "version": "1.2.3" }
    },
    {
      "identity": "alpha",
      "kind": "remoteSourceControl",
      "location": "https://github.com/example/alpha",
      "state": { "revision": "def" }
    },
    {
      "identity": "codeeditsourceeditor",
      "kind": "remoteSourceControl",
      "location": "https://github.com/example/CodeEditSourceEditor.git",
      "state": { "revision": "ghi", "version": "0.1.0" }
    },
    {
      "identity": "CodeEditTextView",
      "kind": "remoteSourceControl",
      "location": "https://github.com/example/CodeEditTextView.git",
      "state": { "revision": "jkl", "version": "0.2.0" }
    }
  ],
  "version": 2
}
"""

@MainActor
@Suite(.uiGate)
struct AboutAcknowledgementsModelCoverageTests {
    @Test
    func missingPackageFileYieldsNoDependencies() {
        let model = AcknowledgementsViewModel(packageResolvedPath: nil)
        #expect(model.acknowledgements.isEmpty)
        #expect(model.indexedAcknowledgements.isEmpty)
    }

    @Test
    func bundledPackageFileIsParsed() {
        #expect(AcknowledgementsViewModel().acknowledgements.isEmpty == false)
    }

    @Test
    func pinsAreSortedFilteredAndMapped() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Package.resolved")
            try aboutCoveragePackagesJSON.write(to: file, atomically: true, encoding: .utf8)

            let model = AcknowledgementsViewModel(packageResolvedPath: file.path)

            #expect(model.acknowledgements.map(\.name) == ["alpha", "Zeta"])
            #expect(model.acknowledgements.map(\.version) == ["-", "1.2.3"])
            #expect(model.acknowledgements.map(\.repositoryLink) == [
                "https://github.com/example/alpha",
                "https://github.com/example/Zeta.git"
            ])
            #expect(model.indexedAcknowledgements.map(\.index) == [0, 1])
            #expect(model.indexedAcknowledgements.map(\.acknowledgement.name) == ["alpha", "Zeta"])
        }
    }

    @Test
    func refetchReplacesPreviousDependencies() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Package.resolved")
            try aboutCoveragePackagesJSON.write(to: file, atomically: true, encoding: .utf8)
            let model = AcknowledgementsViewModel(packageResolvedPath: file.path)

            model.fetchDependencies()

            #expect(model.acknowledgements.count == 2)
        }
    }

    @Test
    func explicitDependenciesAreKeptWithoutFetching() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Package.resolved")
            try aboutCoveragePackagesJSON.write(to: file, atomically: true, encoding: .utf8)
            let given = AcknowledgementDependency(name: "Given", repositoryLink: "https://example.com/", version: "9")

            let model = AcknowledgementsViewModel([given], packageResolvedPath: file.path)

            #expect(model.acknowledgements.map(\.name) == ["Given"])
        }
    }

    @Test
    func invalidJSONLeavesNoDependencies() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Package.resolved")
            try "not json".write(to: file, atomically: true, encoding: .utf8)

            let model = AcknowledgementsViewModel(packageResolvedPath: file.path)

            #expect(model.acknowledgements.isEmpty)
        }
    }

    @Test
    func unreadableFileLeavesNoDependencies() throws {
        try withTempDir { dir in
            let model = AcknowledgementsViewModel(packageResolvedPath: dir.appendingPathComponent("missing").path)

            #expect(model.acknowledgements.isEmpty)
        }
    }

    @Test
    func repositoryURLFallsBackToRoot() {
        let valid = AcknowledgementDependency(name: "a", repositoryLink: "https://example.com/a", version: "1")
        let invalid = AcknowledgementDependency(name: "b", repositoryLink: "", version: "1")

        #expect(valid.repositoryURL.absoluteString == "https://example.com/a")
        #expect(invalid.repositoryURL.path == "/")
    }

    @Test
    func pinNameFallsBackToIdentity() throws {
        let json = Data(#"{"pins":[{"identity":"ident","location":"","state":{"revision":"r"}}]}"#.utf8)
        let object = try JSONDecoder().decode(AcknowledgementObject.self, from: json)

        #expect(object.pins.first?.name == "ident")
        #expect(object.pins.first?.state.version == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct AboutViewsCoverageTests {
    @Test
    func footerRenders() async throws {
        let box = AboutMeasuredSize()
        let host = HostedViewFixture.host(size: NSSize(width: 300, height: 100)) {
            AboutFooterView()
                .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { box.size = $0 })
        }
        defer { host.close() }

        try await eventually(timeout: .seconds(30)) {
            host.layout()
            return box.size.height > 0
        }

        #expect(box.size.width > 0)
        #expect(host.renders())
    }

    @Test
    func subtitleCopiesVersionToInjectedPasteboard() {
        let pasteboard = InMemoryPasteboard()
        let view = AboutSubtitleView(pasteboard: pasteboard)

        view.copyVersion()

        let copied = pasteboard.plainText ?? ""
        #expect(copied.hasPrefix("Dreamder: \(Bundle.versionString ?? "No Version") (\(Bundle.buildString ?? "No Build"))"))
        #expect(copied.contains("\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersion.semverString)"))
    }

    @Test
    func missingBundleValuesFallBackToPlaceholders() {
        let missing = AboutVersion(version: nil, build: nil, postfix: nil)
        let present = AboutVersion(version: "1.2", build: "34", postfix: "-beta")

        #expect(missing.shortDescription == "No Version (No Build)")
        #expect(missing.longDescription == "No Version (No Build)")
        #expect(present.shortDescription == "1.2 (34)")
        #expect(present.longDescription == "1.2-beta (34)")
    }

    @Test
    func theCurrentVersionReadsTheMainBundle() {
        let current = AboutVersion.current

        #expect(current == AboutVersion(
            version: Bundle.versionString,
            build: Bundle.buildString,
            postfix: Bundle.versionPostfix
        ))
    }

    @Test
    func theFooterCopyrightFallsBackToEmptyText() {
        #expect(AboutFooterView.copyrightText(nil) == "")
        #expect(AboutFooterView.copyrightText("Copyright") == "Copyright")
    }

    @Test
    func subtitleHoverTogglesIndicator() {
        let pasteboard = InMemoryPasteboard()
        AboutSubtitleView(pasteboard: pasteboard).setHovering(true)
        AboutSubtitleView(pasteboard: pasteboard).setHovering(false)

        let size = NSSize(width: 400, height: 120)
        let plain = HostedViewFixture.host(size: size) {
            AboutSubtitleView(pasteboard: pasteboard).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        let hovered = HostedViewFixture.host(size: size) {
            AboutSubtitleView(pasteboard: pasteboard, isHoveringVersion: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        defer {
            plain.close()
            hovered.close()
        }

        #expect(HostedView.pixelsDiffer(plain.snapshot(), hovered.snapshot()))
    }

    @Test
    func blurStyleHeightFollowsControlSize() async throws {
        func height(_ style: BlurButtonStyle, _ size: ControlSize) async throws -> CGFloat {
            let box = AboutMeasuredSize()
            let host = HostedViewFixture.host(size: NSSize(width: 300, height: 100)) {
                Button("Go") {}
                    .buttonStyle(style)
                    .controlSize(size)
                    .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { box.size = $0 })
            }
            defer { host.close() }
            try await eventually(timeout: .seconds(30)) {
                host.layout()
                return box.size.height > 0
            }
            return box.size.height
        }

        #expect(try await height(.blur, .regular) == 20)
        #expect(try await height(.secondaryBlur, .small) == 20)
        #expect(try await height(.blur, .large) == 28)
        #expect(try await height(.secondaryBlur, .large) == 28)
    }

    @Test
    func rowRenders() {
        let dependency = AcknowledgementDependency(name: "Row", repositoryLink: "https://example.com/row", version: "1")
        let host = HostedViewFixture.host(size: NSSize(width: 400, height: 100)) {
            AcknowledgementRowView(acknowledgement: dependency)
        }
        defer { host.close() }

        #expect(host.renders())
    }

    @Test
    func listRendersRowsWithDividers() {
        let model = AcknowledgementsViewModel([
            AcknowledgementDependency(name: "One", repositoryLink: "https://example.com/1", version: "1"),
            AcknowledgementDependency(name: "Two", repositoryLink: "https://example.com/2", version: "2")
        ])
        let empty = AcknowledgementsViewModel(packageResolvedPath: nil)
        let full = HostedViewFixture.host(size: NSSize(width: 300, height: 300)) {
            AcknowledgementsListView(model: model)
        }
        let none = HostedViewFixture.host(size: NSSize(width: 300, height: 300)) {
            AcknowledgementsListView(model: empty)
        }
        defer {
            full.close()
            none.close()
        }

        #expect(HostedView.pixelsDiffer(full.snapshot(), none.snapshot()))
    }

    @Test
    func acknowledgementsPageBuildsDetailView() {
        _ = AcknowledgementsView().body
    }
}
