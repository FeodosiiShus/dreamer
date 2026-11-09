import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SignatureHelpViewTests {
    private typealias Fixtures = SignatureHelpFixtures

    private func presentation(_ help: SignatureHelp) throws -> SignatureHelpPresentation {
        try #require(SignatureHelpPresentation(help: help))
    }

    private func documentedHelp() -> SignatureHelp {
        let first = SignatureInformation(
            label: "send(to: String, body: String)",
            documentation: .optionB(MarkupContent(kind: .markdown, value: "Sends a **message** to someone")),
            parameters: [
                ParameterInformation(label: .optionA("to: String"), documentation: .optionA("The recipient")),
                ParameterInformation(
                    label: .optionA("body: String"),
                    documentation: .optionB(MarkupContent(kind: .plaintext, value: "The text of the message"))
                )
            ],
            activeParameter: 1
        )
        let second = Fixtures.signature("to: String", name: "send", documentation: String(repeating: "long ", count: 80))
        return Fixtures.help([first, second], activeSignature: 0)
    }

    private func runs(of text: AttributedString) -> [(text: String, font: Font?)] {
        text.runs.map { run in
            let font: Font? = run.font
            return (String(text[run.range].characters), font)
        }
    }

    @Test
    func labelTextBoldsOnlyTheActiveParameter() throws {
        let row = try presentation(Fixtures.help([Fixtures.signature("a: Int", "b: String")], activeParameter: 1)).rows[0]

        let pieces = runs(of: SignatureHelpText.label(of: row))

        #expect(pieces.map(\.text) == ["function(a: Int, ", "b: String", ")"])
        #expect(pieces.map { $0.font == Islands.codeFont.bold() } == [false, true, false])
    }

    @Test
    func labelTextWithoutAnActiveParameterHasNoBoldRun() throws {
        let row = try presentation(Fixtures.help([Fixtures.signature("a: Int")])).rows[0]

        let pieces = runs(of: SignatureHelpText.label(of: row))

        #expect(pieces.map(\.text) == ["function(a: Int)"])
        #expect(pieces.allSatisfy { $0.font == Islands.codeFont })
    }

    @Test
    func plainDocumentationKeepsMarkdownSyntaxLiteral() throws {
        let documentation = try #require(SignatureHelpDocumentation(.optionA("keeps **stars**")))

        let text = SignatureHelpText.documentation(documentation)

        #expect(String(text.characters) == "keeps **stars**")
    }

    @Test
    func markdownDocumentationRendersInlineEmphasis() throws {
        let documentation = try #require(
            SignatureHelpDocumentation(.optionB(MarkupContent(kind: .markdown, value: "Sends a **message**")))
        )

        let text = SignatureHelpText.documentation(documentation)

        #expect(String(text.characters) == "Sends a message")
        #expect(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test
    func viewModelFollowsTheAppliedPresentation() throws {
        let overloads = try presentation(Fixtures.twoOverloads())
        let model = SignatureHelpViewModel(presentation: overloads)

        #expect(model.rows.count == 2)
        #expect(model.activeIndex == 0)
        #expect(model.showsSwitchHint)

        model.apply(overloads.cycled(by: 1))
        #expect(model.activeIndex == 1)

        model.apply(try presentation(Fixtures.oneOverload()))
        #expect(model.rows.count == 1)
        #expect(!model.showsSwitchHint)
    }

    @Test
    func panelWidthIsClampedBetweenTheMinimumAndMaximum() throws {
        let short = try presentation(Fixtures.help([SignatureInformation(label: "f()")]))
        let long = try presentation(Fixtures.help([SignatureInformation(label: String(repeating: "x", count: 400))]))

        #expect(SignatureHelpMetrics.panelWidth(for: short.rows) == SignatureHelpMetrics.minimumWidth)
        #expect(SignatureHelpMetrics.panelWidth(for: long.rows) == SignatureHelpMetrics.maximumWidth)
    }

    @Test
    func panelWidthGrowsWithTheLabelAndLongDocumentationIsCapped() throws {
        let label = String(repeating: "x", count: 40)
        let plain = try presentation(Fixtures.help([SignatureInformation(label: label)]))
        let documented = try presentation(
            Fixtures.help([SignatureInformation(label: "f()", documentation: .optionA(String(repeating: "word ", count: 200)))])
        )

        let expectedLabelWidth = SignatureHelpMetrics.textWidth(label, font: SignatureHelpMetrics.labelFont)
            + 2 * (SignatureHelpMetrics.horizontalInset + SignatureHelpMetrics.rowInset)
        #expect(SignatureHelpMetrics.panelWidth(for: plain.rows) == min(ceil(expectedLabelWidth), SignatureHelpMetrics.maximumWidth))
        let documentedWidth = SignatureHelpMetrics.panelWidth(for: documented.rows)
        #expect(documentedWidth <= SignatureHelpMetrics.preferredDocumentationWidth
            + 2 * (SignatureHelpMetrics.horizontalInset + SignatureHelpMetrics.rowInset))
        #expect(documentedWidth >= SignatureHelpMetrics.minimumWidth)
    }

    @Test
    func documentationWrapsAtMostToTheLineLimit() {
        let text = String(repeating: "word ", count: 100)

        #expect(SignatureHelpMetrics.documentationLines("short", availableWidth: 2_000) == 1)
        #expect(SignatureHelpMetrics.documentationLines(text, availableWidth: 300) == SignatureHelpMetrics.documentationLineLimit)
        #expect(SignatureHelpMetrics.documentationLines(text, availableWidth: 0) == SignatureHelpMetrics.documentationLineLimit)
        #expect(SignatureHelpMetrics.documentationLines("", availableWidth: 300) == 1)
    }

    @Test
    func rowsWithDocumentationAreTallerAndOverloadsAddTheSwitchHint() throws {
        let plain = try presentation(Fixtures.oneOverload())
        let documented = try presentation(documentedHelp())
        let twoPlain = try presentation(Fixtures.twoOverloads())

        let plainHeight = SignatureHelpMetrics.rowHeight(for: plain.rows[0], availableWidth: 400)
        let documentedHeight = SignatureHelpMetrics.rowHeight(for: documented.rows[0], availableWidth: 400)

        #expect(documentedHeight > plainHeight)
        let single = SignatureHelpMetrics.size(for: plain.rows)
        let double = SignatureHelpMetrics.size(for: twoPlain.rows)
        #expect(double.height > single.height + plainHeight)
        #expect(single.height == ceil(2 * SignatureHelpMetrics.verticalInset + plainHeight))
    }

    @Test
    func viewRendersEveryVariantInAHostedWindow() async throws {
        let variants = [
            try presentation(Fixtures.oneOverload()),
            try presentation(Fixtures.twoOverloads(activeSignature: 1, activeParameter: 2)),
            try presentation(documentedHelp())
        ]
        var cyclingChangedPixels: [Bool] = []
        for variant in variants {
            let model = SignatureHelpViewModel(presentation: variant)
            let hosted = HostedViewFixture.host(size: SignatureHelpMetrics.size(for: variant.rows)) {
                SignatureHelpView(model: model)
            }
            defer { hosted.close() }

            hosted.layout()
            try await hosted.settle(.milliseconds(150))
            #expect(hosted.renders())
            let before = hosted.snapshot()
            model.apply(variant.cycled(by: 1))
            hosted.layout()
            try await hosted.settle(.milliseconds(150))

            #expect(hosted.renders())
            cyclingChangedPixels.append(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
        #expect(cyclingChangedPixels.dropFirst().allSatisfy { $0 })
    }
}
