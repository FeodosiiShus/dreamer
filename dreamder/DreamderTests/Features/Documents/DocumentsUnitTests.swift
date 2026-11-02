//
//  DocumentsUnitTests.swift
//  DreamderTests
//
//  Created by YAPRYNTSEV Aleksey on 31.12.2022.
//

import XCTest
@testable import Dreamder

@MainActor
final class DocumentsUnitTests: XCTestCase {
    private var splitViewController: DreamderSplitViewController!
    private var window: NSWindow!
    private var workspace: WorkspaceDocument!

    override func setUp() {
        super.setUp()
        workspace = WorkspaceDocument()
        workspace.taskManager = TaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        window = NSWindow()
        splitViewController = .init(workspace: workspace, windowRef: window)
        splitViewController.viewDidLoad()
    }

    override func tearDown() {
        splitViewController = nil
        window = nil
        workspace = nil
        super.tearDown()
    }

    func testHostsSingleWorkspaceItem() {
        XCTAssertEqual(
            splitViewController.splitViewItems.count,
            1,
            "The islands layout is hosted in a single split view item."
        )
    }

    func testWorkspaceItemCannotBeCollapsed() {
        XCTAssertFalse(splitViewController.splitViewItems.first?.canCollapse ?? true)
    }
}
