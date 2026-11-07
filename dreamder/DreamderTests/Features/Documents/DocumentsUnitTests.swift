//
//  DocumentsUnitTests.swift
//  DreamderTests
//
//  Created by YAPRYNTSEV Aleksey on 31.12.2022.
//

import SwiftUI
import XCTest
@testable import Dreamder

@MainActor
final class DocumentsUnitTests: XCTestCase {
    private var hostingController: WorkspaceHostingController!
    private var window: NSWindow!
    private var workspace: WorkspaceDocument!

    override func setUp() async throws {
        workspace = WorkspaceDocument()
        workspace.taskManager = TaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        window = NSWindow()
        hostingController = WorkspaceHostingController(workspace: workspace, windowRef: window)
    }

    override func tearDown() async throws {
        hostingController = nil
        window = nil
        workspace = nil
    }

    func testHostingControllerIsCreatedForAFullyInitializedWorkspace() {
        XCTAssertNotNil(hostingController)
    }

    func testHostingControllerIsNotCreatedWithoutTaskManager() {
        workspace.taskManager = nil

        XCTAssertNil(WorkspaceHostingController(workspace: workspace, windowRef: window))
    }

    func testHostingControllerDoesNotDriveWindowSizeFromContent() {
        XCTAssertEqual(hostingController.sizingOptions, [])
    }

    func testViewIsInstalledAsHostingView() {
        XCTAssertTrue(hostingController.view is NSHostingView<AnyView>)
    }

    func testViewWillAppearRestoresStoredToolWindowLayout() {
        let stored = ToolWindowLayout(
            left: nil,
            bottom: nil,
            leftWidth: 333,
            bottomHeight: 211,
            bottomMaximized: false
        )
        stored.save(to: workspace)
        workspace.toolWindowManager.show(.project)

        hostingController.viewWillAppear()

        XCTAssertNil(workspace.toolWindowManager.visible(on: .left, side: .main))
        XCTAssertNil(workspace.toolWindowManager.visible(on: .bottom, side: .main))
        XCTAssertEqual(workspace.toolWindowManager.leftWidth, 333)
        XCTAssertEqual(workspace.toolWindowManager.bottomHeight, 211)
    }
}
