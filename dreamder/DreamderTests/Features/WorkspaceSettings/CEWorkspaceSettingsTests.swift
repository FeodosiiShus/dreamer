//
//  CEWorkspaceSettingsTests.swift
//  DreamderTests
//
//  Created by Khan Winter on 4/21/25.
//

import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceSettingsTests {
    let settings: CEWorkspaceSettings = CEWorkspaceSettings(workspaceURL: URL(filePath: "/"))

    @Test
    func settingsURLNoSpace() async throws {
        #expect(settings.folderURL.lastPathComponent == ".dreamder")
        #expect(settings.settingsURL.lastPathComponent == "settings.json")
    }
}
