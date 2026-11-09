import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct KeymapTests {
    private func withKeymap(_ body: (Keymap, UserDefaults) throws -> Void) throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try body(Keymap(defaults: defaults), defaults)
    }

    private let commandB = Shortcut.stroke("b", .command)

    @Test
    func untouchedKeymapReturnsTheDefaults() throws {
        try withKeymap { keymap, _ in
            for command in KeymapCommand.allCases {
                #expect(keymap.shortcuts(for: command) == command.defaultShortcuts)
                #expect(!keymap.isModified(command))
            }
            #expect(keymap.overrides.isEmpty)
        }
    }

    @Test
    func keyboardShortcutsAreBuiltFromTheStoredStrokes() throws {
        try withKeymap { keymap, _ in
            #expect(keymap.keyboardShortcut(for: .goToDeclaration) == KeyboardShortcut("b", modifiers: .command))
            #expect(
                keymap.keyboardShortcut(for: .findUsages)
                    == KeyboardShortcut(KeyEquivalent("\u{F70A}"), modifiers: .option)
            )
            #expect(keymap.keyboardShortcut(for: .quickDocumentation) == KeyboardShortcut("j", modifiers: .control))
            #expect(
                keymap.keyboardShortcut(for: .quickDocumentation, at: 1)
                    == KeyboardShortcut(KeyEquivalent("\u{F704}"), modifiers: [])
            )
            #expect(keymap.keyboardShortcut(for: .quickDocumentation, at: 2) == nil)
            #expect(keymap.keyboardShortcut(for: .goToClass) == nil)
        }
    }

    @Test
    func doubleModifierShortcutsProduceNoMenuShortcut() throws {
        try withKeymap { keymap, _ in
            #expect(keymap.shortcuts(for: .searchEverywhere) == [.doubleModifier(.shift)])
            #expect(keymap.keyboardShortcut(for: .searchEverywhere) == nil)
        }
    }

    @Test
    func everyCommandWithAKeyStrokeDefaultExposesItsRegistryShortcut() throws {
        try withKeymap { keymap, _ in
            for command in KeymapCommand.allCases {
                let strokes = command.defaultShortcuts.compactMap(\.keyStroke)
                for (index, stroke) in strokes.enumerated() {
                    #expect(keymap.keyboardShortcut(for: command, at: index) == stroke.keyboardShortcut, "\(command.id)")
                }
            }
        }
    }

    @Test
    func replacingShortcutsChangesTheMenuShortcut() throws {
        try withKeymap { keymap, _ in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", [.option, .command]))

            #expect(keymap.shortcuts(for: .goToDeclaration) == [.stroke("d", [.option, .command])])
            #expect(keymap.isModified(.goToDeclaration))
            #expect(
                keymap.keyboardShortcut(for: .goToDeclaration)
                    == KeyboardShortcut("d", modifiers: [.option, .command])
            )
        }
    }

    @Test
    func addingKeepsExistingShortcutsAndIgnoresDuplicates() throws {
        try withKeymap { keymap, _ in
            keymap.addShortcut(.stroke("d", [.option, .command]), to: .goToDeclaration)
            keymap.addShortcut(.stroke("d", [.option, .command]), to: .goToDeclaration)

            #expect(keymap.shortcuts(for: .goToDeclaration) == [commandB, .stroke("d", [.option, .command])])
            #expect(keymap.keyboardShortcut(for: .goToDeclaration, at: 1) != nil)
        }
    }

    @Test
    func addingToACommandWithoutDefaultsCreatesAnOverride() throws {
        try withKeymap { keymap, _ in
            keymap.addShortcut(.stroke("y", .command), to: .goToClass)

            #expect(keymap.shortcuts(for: .goToClass) == [.stroke("y", .command)])
            #expect(keymap.isModified(.goToClass))
        }
    }

    @Test
    func removingASingleShortcutKeepsTheOthers() throws {
        try withKeymap { keymap, _ in
            keymap.removeShortcut(.stroke("j", .control), from: .quickDocumentation)

            #expect(keymap.shortcuts(for: .quickDocumentation) == [.stroke(KeyNames.f1)])
            #expect(keymap.keyboardShortcut(for: .quickDocumentation) != nil)
        }
    }

    @Test
    func removingAllShortcutsYieldsNoMenuShortcut() throws {
        try withKeymap { keymap, _ in
            keymap.removeAllShortcuts(from: .goToDeclaration)

            #expect(keymap.shortcuts(for: .goToDeclaration).isEmpty)
            #expect(keymap.isModified(.goToDeclaration))
            #expect(keymap.keyboardShortcut(for: .goToDeclaration) == nil)
        }
    }

    @Test
    func removingAllShortcutsFromACommandWithoutDefaultsIsNotAnOverride() throws {
        try withKeymap { keymap, _ in
            keymap.removeAllShortcuts(from: .goToClass)

            #expect(!keymap.isModified(.goToClass))
        }
    }

    @Test
    func restoringTheDefaultsDropsTheOverrideRegardlessOfOrder() throws {
        try withKeymap { keymap, _ in
            keymap.replaceShortcuts(of: .quickDocumentation, with: .stroke("q", .control))
            keymap.addShortcut(.stroke(KeyNames.f1), to: .quickDocumentation)
            keymap.addShortcut(.stroke("j", .control), to: .quickDocumentation)
            keymap.removeShortcut(.stroke("q", .control), from: .quickDocumentation)

            #expect(keymap.shortcuts(for: .quickDocumentation) == KeymapCommand.quickDocumentation.defaultShortcuts)
            #expect(!keymap.isModified(.quickDocumentation))
        }
    }

    @Test
    func resettingACommandRestoresItsDefaults() throws {
        try withKeymap { keymap, _ in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", .option))
            keymap.replaceShortcuts(of: .find, with: .stroke("f", .control))
            keymap.reset(.goToDeclaration)

            #expect(keymap.shortcuts(for: .goToDeclaration) == [commandB])
            #expect(keymap.isModified(.find))
        }
    }

    @Test
    func resettingEverythingClearsAllOverrides() throws {
        try withKeymap { keymap, defaults in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", .option))
            keymap.removeAllShortcuts(from: .find)
            keymap.resetAll()

            #expect(keymap.overrides.isEmpty)
            #expect(defaults.data(forKey: Keymap.storageKey) == nil)
            #expect(keymap.shortcuts(for: .find) == KeymapCommand.find.defaultShortcuts)
        }
    }

    @Test
    func overridesPersistAndReloadFromTheSameSuite() throws {
        try withKeymap { keymap, defaults in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", [.option, .command]))
            keymap.removeAllShortcuts(from: .find)
            keymap.addShortcut(.doubleModifier(.command), to: .goToClass)

            let reloaded = Keymap(defaults: defaults)

            #expect(reloaded.overrides == keymap.overrides)
            #expect(reloaded.shortcuts(for: .goToDeclaration) == [.stroke("d", [.option, .command])])
            #expect(reloaded.shortcuts(for: .find).isEmpty)
            #expect(reloaded.shortcuts(for: .goToClass) == [.doubleModifier(.command)])
            #expect(reloaded.shortcuts(for: .save) == KeymapCommand.save.defaultShortcuts)
        }
    }

    @Test
    func resetsPersistAsWell() throws {
        try withKeymap { keymap, defaults in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", .option))
            keymap.replaceShortcuts(of: .find, with: .stroke("f", .control))
            keymap.reset(.goToDeclaration)

            let reloaded = Keymap(defaults: defaults)

            #expect(reloaded.overrides.keys.sorted { $0.id < $1.id } == [.find])
        }
    }

    @Test
    func differentSuitesDoNotShareOverrides() throws {
        try withKeymap { keymap, _ in
            keymap.replaceShortcuts(of: .goToDeclaration, with: .stroke("d", .option))

            try withKeymap { other, _ in
                #expect(other.overrides.isEmpty)
            }
        }
    }

    @Test
    func storedDataIsToleratedWhenItIsStaleOrCorrupt() throws {
        try withKeymap { _, defaults in
            let stored = [
                "navigate.goToDeclaration": ["command b"],
                "navigate.goToClass": ["command y", "garbage text here", "command"],
                "removed.command": ["command q"],
                "find.find": []
            ]
            defaults.set(try JSONEncoder().encode(stored), forKey: Keymap.storageKey)

            let keymap = Keymap(defaults: defaults)

            #expect(!keymap.isModified(.goToDeclaration))
            #expect(keymap.shortcuts(for: .goToClass) == [.stroke("y", .command)])
            #expect(keymap.shortcuts(for: .find).isEmpty)
            #expect(keymap.overrides.count == 2)

            defaults.set(Data("not json".utf8), forKey: Keymap.storageKey)
            #expect(Keymap(defaults: defaults).overrides.isEmpty)
        }
    }

    @Test
    func conflictsListOtherCommandsWithTheSameShortcut() throws {
        try withKeymap { keymap, _ in
            #expect(keymap.conflicts(for: commandB, excluding: .goToTypeDeclaration) == [.goToDeclaration])
            #expect(keymap.conflicts(for: commandB, excluding: .goToDeclaration).isEmpty)
            #expect(keymap.conflicts(for: .stroke("b", [.shift, .command]), excluding: .goToDeclaration) == [.goToTypeDeclaration])
            #expect(keymap.conflicts(for: .stroke("b", .option), excluding: .goToDeclaration).isEmpty)
            #expect(keymap.conflicts(for: .doubleModifier(.shift), excluding: .goToDeclaration) == [.searchEverywhere])
        }
    }

    @Test
    func conflictsFollowOverridesAndKeepRegistryOrder() throws {
        try withKeymap { keymap, _ in
            keymap.addShortcut(commandB, to: .findAction)
            keymap.addShortcut(commandB, to: .save)

            #expect(keymap.conflicts(for: commandB, excluding: .find) == [.save, .findAction, .goToDeclaration])
            #expect(keymap.conflicts(of: .goToDeclaration) == [.save, .findAction])
            #expect(keymap.conflicts(of: .save) == [.findAction, .goToDeclaration])
            #expect(keymap.conflicts(of: .find).isEmpty)
        }
    }

    @Test
    func aCommandConflictsOnceEvenWhenSeveralShortcutsCollide() throws {
        try withKeymap { keymap, _ in
            keymap.addShortcut(.stroke("b", .command), to: .goToClass)
            keymap.addShortcut(.stroke("b", [.shift, .command]), to: .goToClass)

            #expect(keymap.conflicts(of: .goToClass) == [.goToDeclaration, .goToTypeDeclaration])
        }
    }

    @Test
    func removingTheConflictingBindingResolvesIt() throws {
        try withKeymap { keymap, _ in
            keymap.addShortcut(commandB, to: .save)
            keymap.removeShortcut(commandB, from: .goToDeclaration)

            #expect(keymap.conflicts(of: .save).isEmpty)
            #expect(keymap.shortcuts(for: .goToDeclaration).isEmpty)
        }
    }

    @Test
    func theDefaultKeymapHasNoConflicts() throws {
        try withKeymap { keymap, _ in
            for command in KeymapCommand.allCases {
                #expect(keymap.conflicts(of: command).isEmpty, "\(command.id)")
            }
        }
    }

    @Test
    func theSharedKeymapReadsTheStandardDefaults() {
        #expect(Keymap.shared.shortcuts(for: .goToFile) == KeymapCommand.goToFile.defaultShortcuts
            || Keymap.shared.isModified(.goToFile))
    }

    @Test
    func menuItemsReceiveTheFirstKeyStrokeAndTheMatchingModifiers() throws {
        try withKeymap { keymap, _ in
            let item = NSMenuItem(title: "Push", action: nil, keyEquivalent: "")

            keymap.apply(.gitPush, to: item)
            #expect(item.keyEquivalent == "k")
            #expect(item.keyEquivalentModifierMask == [.command, .shift])

            keymap.apply(.quickDocumentation, to: item)
            #expect(item.keyEquivalent == "j")
            #expect(item.keyEquivalentModifierMask == .control)

            keymap.replaceShortcuts(of: .gitPush, with: .stroke(KeyNames.f7, [.control, .option]))
            keymap.apply(.gitPush, to: item)
            #expect(item.keyEquivalent == String(KeyNames.f7))
            #expect(item.keyEquivalentModifierMask == [.control, .option])
        }
    }

    @Test
    func menuItemsLoseTheirKeyEquivalentWhenTheShortcutIsClearedOrIsADoubleModifier() throws {
        try withKeymap { keymap, _ in
            let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: ",")

            keymap.removeAllShortcuts(from: .settings)
            keymap.apply(.settings, to: item)
            #expect(item.keyEquivalent.isEmpty)
            #expect(item.keyEquivalentModifierMask.isEmpty)

            keymap.apply(.searchEverywhere, to: item)
            #expect(item.keyEquivalent.isEmpty)
        }
    }
}
