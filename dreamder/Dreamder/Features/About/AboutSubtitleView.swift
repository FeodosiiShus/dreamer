//
//  AboutSubtitleView.swift
//  Dreamder
//
//  Created by Giorgi Tchelidze on 08.06.25.
//

import SwiftUI

struct AboutSubtitleView: View {

    @State private var didCopyVersion = false
    @State private var isHoveringVersion: Bool

    private let pasteboard: any PasteboardAccess

    init(pasteboard: any PasteboardAccess = SystemPasteboard(), isHoveringVersion: Bool = false) {
        self.pasteboard = pasteboard
        _isHoveringVersion = State(initialValue: isHoveringVersion)
    }

    private var version: AboutVersion { AboutVersion.current }

    var body: some View {
        Text("Version \(version.longDescription)")
            .textSelection(.disabled)
            .onTapGesture(perform: copyVersion)
            .background(alignment: .leading) {
                if isHoveringVersion {
                    Image(systemName: "document.on.document.fill")
                        .font(.caption)
                        .offset(x: -16, y: 0)
                        .transition(.opacity)
                        .symbolEffect(
                            .bounce.down.wholeSymbol,
                            options: .nonRepeating.speed(1.8),
                            value: didCopyVersion
                        )
                }
            }
            .onHover(perform: setHovering)
    }

    func copyVersion() {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion.semverString
        pasteboard.replaceContents(
            withText: "Dreamder: \(version.shortDescription)\nmacOS: \(macOSVersion)"
        )
        didCopyVersion.toggle()
    }

    func setHovering(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.1)) {
            isHoveringVersion = hovering
        }
    }
}

struct AboutVersion: Equatable {
    static let missingVersion = "No Version"
    static let missingBuild = "No Build"

    let version: String
    let build: String
    let postfix: String

    init(version: String?, build: String?, postfix: String?) {
        self.version = version ?? Self.missingVersion
        self.build = build ?? Self.missingBuild
        self.postfix = postfix ?? ""
    }

    static var current: AboutVersion {
        AboutVersion(version: Bundle.versionString, build: Bundle.buildString, postfix: Bundle.versionPostfix)
    }

    var shortDescription: String {
        "\(version) (\(build))"
    }

    var longDescription: String {
        "\(version)\(postfix) (\(build))"
    }
}
