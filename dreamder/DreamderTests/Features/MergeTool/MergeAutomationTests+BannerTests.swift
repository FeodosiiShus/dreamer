import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    @Test
    func clickChipTriggersTheChipActionInThePane() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            try await eventually(timeout: .seconds(30)) {
                paneTextView("left")?.string.contains("zeta-main") == true
                    && paneTextView("right")?.string.contains("zeta-feature") == true
            }

            for command in [
                "clickChip:left:\(blockID):right",
                "clickChip:right:\(blockID):left",
                "clickChip:result:\(blockID):left",
                "clickChip:middle:\(blockID):left",
                "clickChip:left:abc:left",
                "clickChip:left:\(blockID)",
                "clickChip:left:\(blockID):left:extra",
                "clickChip:left:\(blockID):bogus"
            ] {
                await MergeAutomation.perform(command)
                #expect(model.merge?.conflictCount == 1)
            }

            await MergeAutomation.perform("clickChip:left:\(blockID):left")

            #expect(model.merge?.conflictCount == 0)
            #expect(model.resultText.contains("epsilon\nzeta-main\neta"))
        }
    }

    @Test(arguments: [
        ("right", "right", "epsilon\nzeta-feature\neta"),
        ("left", "ignore", "epsilon\nzeta\neta"),
        ("right", "ignore", "epsilon\nzeta\neta")
    ])
    func clickChipSupportsEveryPaneAndAction(pane: String, action: String, expectedFragment: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            try await eventually(timeout: .seconds(30)) {
                paneTextView(pane)?.string.contains("zeta") == true
            }

            await MergeAutomation.perform("clickChip:\(pane):\(blockID):\(action)")

            #expect(model.merge?.conflictCount == 0)
            #expect(model.resultText.contains(expectedFragment))
        }
    }

    @Test
    func confirmCommandAnswersTheNextQuestionOnce() async {
        await MergeAutomation.perform("confirm:yes")
        #expect(MergeToolConfirmation.automationAnswer == true)
        let first = await MergeToolConfirmation.ask(
            window: nil,
            title: "t",
            message: "m",
            confirmTitle: "c",
            cancelTitle: "x"
        )
        #expect(first)
        #expect(MergeToolConfirmation.automationAnswer == nil)

        await MergeAutomation.perform("confirm:no")
        #expect(MergeToolConfirmation.automationAnswer == false)
        let second = await MergeToolConfirmation.ask(
            window: nil,
            title: "t",
            message: "m",
            confirmTitle: "c",
            cancelTitle: "x"
        )
        #expect(second == false)
        #expect(MergeToolConfirmation.automationAnswer == nil)

        await MergeAutomation.perform("confirm:maybe")
        #expect(MergeToolConfirmation.automationAnswer == false)
        MergeToolConfirmation.automationAnswer = nil
    }

    @Test
    func bannerResolveInvokesTheRegisteredBannerAction() async {
        let counter = InvocationCounter()
        MergeAutomation.registerBanner(path: "app/config.txt") { counter.value += 1 }

        await MergeAutomation.perform("bannerResolve")
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 2)

        MergeAutomation.registerBanner(path: nil, action: nil)
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 2)
    }

    @Test
    func theBannerDefaultsRegisterWithTheAutomationAndShowRevisionsThroughThePresenter() async {
        let banner = MergeConflictEditorBanner(fileURL: URL(fileURLWithPath: "/private/tmp/dreamder-banner.txt"))
        let counter = InvocationCounter()

        banner.registerAutomation("app/config.txt", { counter.value += 1 })
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 1)

        banner.registerAutomation(nil, nil)
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 1)

        let revisionsKey = MergeToolPresenter.lastRevisionsKey
        banner.showMergeRevisions(WorkspaceDocument(), "app/config.txt")
        #expect(MergeToolPresenter.lastRevisionsKey == revisionsKey)
    }

    @Test
    func menuResolveActivatesTheGitMenuItemAndDumpReportsIt() async throws {
        try await withSession { session in
            let probe = MenuProbe()
            let item = NSMenuItem(
                title: "Resolve Conflicts…",
                action: #selector(MenuProbe.resolve(_:)),
                keyEquivalent: ""
            )
            item.target = probe
            let gitMenu = NSMenu(title: "Git")
            gitMenu.addItem(NSMenuItem(title: "Update Project", action: nil, keyEquivalent: ""))
            gitMenu.addItem(item)
            let gitItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
            gitItem.submenu = gitMenu
            let mainMenu = NSMenu()
            mainMenu.addItem(gitItem)

            let savedMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = savedMenu }
            NSApp.mainMenu = mainMenu
            await MergeAutomation.perform("menuResolve")
            let withMenu = try await dumpLines(session)
            NSApp.mainMenu = NSMenu()
            await MergeAutomation.perform("menuResolve")
            let withoutMenu = try await dumpLines(session)

            #expect(probe.invocations == 1)
            #expect(value("menu.resolvePresent", in: withMenu) == "1")
            #expect(value("menu.resolveEnabled", in: withMenu) == "1")
            #expect(value("menu.resolveTitle", in: withMenu) == "Resolve Conflicts…")
            #expect(value("menu.resolvePresent", in: withoutMenu) == "0")
            #expect(value("menu.resolveEnabled", in: withoutMenu) == "0")
            #expect(value("menu.resolveTitle", in: withoutMenu) == "")
        }
    }

    @Test
    func menuResolveReportsADisabledMenuItem() async throws {
        try await withSession { session in
            let probe = MenuProbe()
            let item = NSMenuItem(
                title: "Resolve Conflicts…",
                action: #selector(MenuProbe.resolve(_:)),
                keyEquivalent: ""
            )
            item.target = probe
            item.isEnabled = false
            let gitMenu = NSMenu(title: "Git")
            gitMenu.autoenablesItems = false
            gitMenu.addItem(item)
            let gitItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
            gitItem.submenu = gitMenu
            let mainMenu = NSMenu()
            mainMenu.addItem(gitItem)

            let savedMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = savedMenu }
            NSApp.mainMenu = mainMenu
            let lines = try await dumpLines(session)

            #expect(value("menu.resolvePresent", in: lines) == "1")
            #expect(value("menu.resolveEnabled", in: lines) == "0")
        }
    }
}
