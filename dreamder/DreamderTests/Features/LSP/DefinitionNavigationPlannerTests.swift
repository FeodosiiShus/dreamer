import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("Definition navigation planner")
struct DefinitionNavigationPlannerTests {
    private struct Caret: Sendable {
        let name: String
        let line: Int
        let character: Int
        let hits: Bool
    }

    private static let modelURI = "file:///tmp/project/Sources/Model.swift"
    private static let otherURI = "file:///tmp/project/Sources/Other.swift"
    private let modelFile = URL(fileURLWithPath: "/tmp/project/Sources/Model.swift")

    private static func range(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: Position(line: line, character: start), end: Position(line: line, character: end))
    }

    private static func target(_ uri: String, _ line: Int, _ start: Int = 4, _ end: Int = 9) -> LSPDefinitionTarget {
        let range = range(line, start, end)
        return LSPDefinitionTarget(uri: uri, range: range, selectionRange: range)
    }

    private func origin(_ line: Int, _ character: Int, file: URL? = nil) -> LSPNavigationOrigin {
        LSPNavigationOrigin(fileURL: file ?? modelFile, position: Position(line: line, character: character))
    }

    @Test func kindsCarryTheirTitlesAndMessages() {
        #expect(LSPNavigationKind.declaration.commandName == "Go to Declaration")
        #expect(LSPNavigationKind.implementation.commandName == "Go to Implementation")
        #expect(LSPNavigationKind.typeDeclaration.commandName == "Go to Type Declaration")
        #expect(LSPNavigationKind.declaration.chooserTitle == "Choose Declaration")
        #expect(LSPNavigationKind.implementation.chooserTitle == "Choose Implementation")
        #expect(LSPNavigationKind.typeDeclaration.chooserTitle == "Choose Type Declaration")
        #expect(LSPNavigationKind.declaration.emptyMessage == nil)
        #expect(LSPNavigationKind.implementation.emptyMessage == "No implementations found")
        #expect(LSPNavigationKind.typeDeclaration.emptyMessage == "No type declaration found")
        #expect(
            LSPNavigationKind.implementation.missingServerMessage
                == "Go to Implementation needs a language server for this file"
        )
    }

    @Test func destinationsKeepOrderAndDropDuplicatesByUriAndRange() {
        let first = Self.target(Self.modelURI, 1)
        let second = Self.target(Self.otherURI, 1)
        let sameRangeDifferentBody = LSPDefinitionTarget(
            uri: Self.modelURI,
            range: Self.range(0, 0, 40),
            selectionRange: first.selectionRange
        )
        let otherRange = Self.target(Self.modelURI, 1, 5, 9)

        let destinations = LSPNavigationPlanner.destinations(
            from: [first, second, first, sameRangeDifferentBody, otherRange]
        )

        #expect(destinations.map(\.uri) == [Self.modelURI, Self.otherURI, Self.modelURI])
        #expect(destinations.map(\.range) == [first.selectionRange, second.selectionRange, otherRange.selectionRange])
    }

    @Test func destinationsResolveFileURLsAndDropOtherSchemes() {
        let destinations = LSPNavigationPlanner.destinations(from: [
            Self.target("jar:file:///tmp/lib.jar!/A.class", 0),
            Self.target("https://example.com/a.swift", 0),
            Self.target(Self.modelURI, 7, 2, 6)
        ])

        #expect(destinations.count == 1)
        #expect(destinations.first?.fileURL == LSPDiagnosticMapping.fileURL(fromDocumentURI: Self.modelURI))
        #expect(destinations.first?.line == 8)
        #expect(destinations.first?.column == 3)
    }

    @Test(arguments: [
        Caret(name: "before the name", line: 3, character: 3, hits: false),
        Caret(name: "start of the name", line: 3, character: 4, hits: true),
        Caret(name: "inside the name", line: 3, character: 6, hits: true),
        Caret(name: "end of the name", line: 3, character: 9, hits: true),
        Caret(name: "after the name", line: 3, character: 10, hits: false),
        Caret(name: "line above", line: 2, character: 6, hits: false),
        Caret(name: "line below", line: 4, character: 6, hits: false)
    ])
    private func selfDestinationFollowsTheCaretInsideTheSelectionRange(caret: Caret) {
        let destinations = LSPNavigationPlanner.destinations(from: [Self.target(Self.modelURI, 3)])

        let found = LSPNavigationPlanner.selfDestination(
            in: destinations,
            origin: origin(caret.line, caret.character)
        )

        #expect((found != nil) == caret.hits, "\(caret.name)")
    }

    @Test func selfDestinationIgnoresOtherFilesAndPicksTheFirstMatch() {
        let destinations = LSPNavigationPlanner.destinations(from: [
            Self.target(Self.otherURI, 3),
            Self.target(Self.modelURI, 3, 0, 20),
            Self.target(Self.modelURI, 3, 4, 9)
        ])

        let found = LSPNavigationPlanner.selfDestination(in: destinations, origin: origin(3, 5))

        #expect(found?.range == Self.range(3, 0, 20))
        #expect(
            LSPNavigationPlanner.selfDestination(
                in: destinations,
                origin: origin(3, 5, file: URL(fileURLWithPath: "/tmp/project/Sources/Elsewhere.swift"))
            ) == nil
        )
    }

    @Test func declarationWithoutTargetsShowsUsages() {
        let plan = LSPNavigationPlanner.plan(kind: .declaration, targets: [], origin: origin(0, 0))
        #expect(plan == .showUsages)
    }

    @Test func implementationAndTypeWithoutTargetsShowTheirMessages() {
        #expect(
            LSPNavigationPlanner.plan(kind: .implementation, targets: [], origin: origin(0, 0))
                == .showMessage("No implementations found")
        )
        #expect(
            LSPNavigationPlanner.plan(kind: .typeDeclaration, targets: [], origin: origin(0, 0))
                == .showMessage("No type declaration found")
        )
    }

    @Test func targetsWithoutAFileAreTreatedAsNoTargets() {
        let unsupported = [Self.target("https://example.com/a.swift", 0)]
        #expect(LSPNavigationPlanner.plan(kind: .declaration, targets: unsupported, origin: origin(0, 0)) == .showUsages)
        #expect(
            LSPNavigationPlanner.plan(kind: .implementation, targets: unsupported, origin: origin(0, 0))
                == .showMessage("No implementations found")
        )
    }

    @Test func declarationOnTheDeclarationItselfShowsUsages() {
        let targets = [Self.target(Self.modelURI, 3)]
        #expect(LSPNavigationPlanner.plan(kind: .declaration, targets: targets, origin: origin(3, 6)) == .showUsages)
    }

    @Test func declarationWithOneOtherTargetJumps() throws {
        let targets = [Self.target(Self.otherURI, 12, 2, 8)]

        let plan = LSPNavigationPlanner.plan(kind: .declaration, targets: targets, origin: origin(3, 6))

        guard case .jump(let destination) = plan else {
            Issue.record("expected a jump, got \(plan)")
            return
        }
        #expect(destination.uri == Self.otherURI)
        #expect(destination.line == 13)
        #expect(destination.column == 3)
    }

    @Test func duplicateTargetsCollapseIntoOneJump() {
        let targets = [Self.target(Self.otherURI, 1), Self.target(Self.otherURI, 1)]
        let plan = LSPNavigationPlanner.plan(kind: .declaration, targets: targets, origin: origin(0, 0))
        #expect(plan == .jump(LSPNavigationPlanner.destinations(from: [targets[0]])[0]))
    }

    @Test func declarationWithSeveralTargetsOffersAChooser() {
        let targets = [Self.target(Self.otherURI, 1), Self.target(Self.modelURI, 9)]

        let plan = LSPNavigationPlanner.plan(kind: .declaration, targets: targets, origin: origin(3, 6))

        #expect(plan == .choose(LSPNavigationPlanner.destinations(from: targets)))
    }

    @Test func declarationWithSeveralTargetsIncludingTheCaretShowsUsages() {
        let targets = [Self.target(Self.otherURI, 1), Self.target(Self.modelURI, 3)]
        #expect(LSPNavigationPlanner.plan(kind: .declaration, targets: targets, origin: origin(3, 6)) == .showUsages)
    }

    @Test(arguments: [LSPNavigationKind.implementation, LSPNavigationKind.typeDeclaration])
    private func implementationAndTypeJumpEvenWhenTheTargetIsTheCaretPlace(kind: LSPNavigationKind) {
        let targets = [Self.target(Self.modelURI, 3)]

        let plan = LSPNavigationPlanner.plan(kind: kind, targets: targets, origin: origin(3, 6))

        #expect(plan == .jump(LSPNavigationPlanner.destinations(from: targets)[0]))
    }

    @Test(arguments: [LSPNavigationKind.implementation, LSPNavigationKind.typeDeclaration])
    private func implementationAndTypeWithSeveralTargetsOfferAChooserEvenAtTheCaretPlace(kind: LSPNavigationKind) {
        let targets = [Self.target(Self.modelURI, 3), Self.target(Self.otherURI, 3)]

        let plan = LSPNavigationPlanner.plan(kind: kind, targets: targets, origin: origin(3, 6))

        #expect(plan == .choose(LSPNavigationPlanner.destinations(from: targets)))
    }

    @Test func locationsUseTheSelectionRangeOnTheStartLine() {
        let oneLine = LSPNavigationPlanner.destinations(from: [Self.target(Self.modelURI, 5, 2, 7)])
        let multiLine = LSPNavigationPlanner.destinations(from: [
            LSPDefinitionTarget(
                uri: Self.otherURI,
                range: Self.range(1, 0, 1),
                selectionRange: LSPRange(start: Position(line: 1, character: 3), end: Position(line: 4, character: 8))
            )
        ])

        #expect(
            LSPNavigationPlanner.locations(for: oneLine + multiLine) == [
                LSPReferenceLocation(uri: Self.modelURI, line: 5, startCharacter: 2, endCharacter: 7),
                LSPReferenceLocation(uri: Self.otherURI, line: 1, startCharacter: 3, endCharacter: 3)
            ]
        )
    }

    @Test func previewLineIsTrimmedAndBoundsChecked() {
        let contents = "first\n    let value = 1  \nlast"
        #expect(LSPDefinitionPreview.line(at: 1, in: contents) == "let value = 1")
        #expect(LSPDefinitionPreview.line(at: 0, in: contents) == "first")
        #expect(LSPDefinitionPreview.line(at: 3, in: contents) == nil)
        #expect(LSPDefinitionPreview.line(at: -1, in: contents) == nil)
    }

    @Test func previewLineReadsFilesAndFallsBackToAnEmptyString() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "Preview.swift")
            try "alpha\n    beta()\n".write(to: url, atomically: true, encoding: .utf8)

            #expect(await LSPDefinitionPreview.line(at: 1, in: url) == "beta()")
            #expect(await LSPDefinitionPreview.line(at: 9, in: url) == "")
            #expect(await LSPDefinitionPreview.line(at: 0, in: directory.appending(path: "Missing.swift")) == "")
        }
    }

    @Test func linkKeysCompareByFileLineAndColumn() {
        let key = LSPLinkKey(fileURL: modelFile, line: 1, column: 2)
        #expect(key == LSPLinkKey(fileURL: modelFile, line: 1, column: 2))
        #expect(key != LSPLinkKey(fileURL: modelFile, line: 1, column: 3))
    }
}
