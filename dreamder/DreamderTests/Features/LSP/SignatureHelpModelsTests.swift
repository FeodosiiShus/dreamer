import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct SignatureHelpModelsTests {
    private typealias Fixtures = SignatureHelpFixtures

    private func activeParameterIndex(of help: SignatureHelp) throws -> Int {
        let presentation = try #require(SignatureHelpPresentation(help: help))
        return presentation.rows[presentation.activeIndex].activeParameterIndex
    }

    private func segment(_ text: String, _ isActive: Bool = false) -> SignatureHelpSegment {
        SignatureHelpSegment(text: text, isActiveParameter: isActive)
    }

    @Test
    func lspParameterInfoTestBasicSignatureWithOuterActiveParameter() throws {
        let help = Fixtures.help([Fixtures.signature("param1: String", "param2: Int")], activeParameter: 1)
        let presentation = try #require(SignatureHelpPresentation(help: help))

        #expect(presentation.rows[0].activeParameterIndex == 1)
        #expect(presentation.rows[0].label == "function(param1: String, param2: Int)")
        #expect(presentation.rows[0].segments == [
            segment("function(param1: String, "),
            segment("param2: Int", true),
            segment(")")
        ])
    }

    @Test
    func lspParameterInfoTestBasicSignatureWithInnerActiveParameter() throws {
        let help = Fixtures.help(
            [Fixtures.signature("param1: String", "param2: Int", "param3: Boolean", activeParameter: 2)],
            activeSignature: 0
        )

        #expect(try activeParameterIndex(of: help) == 2)
        #expect(SignatureHelpPresentation(help: help)?.rows[0].label == "function(param1: String, param2: Int, param3: Boolean)")
    }

    @Test
    func lspParameterInfoTestInnerActiveParameterTakesPrecedenceOverOuterOne() throws {
        let help = Fixtures.help([Fixtures.signature("a", "b", activeParameter: 1)], activeParameter: 0)

        #expect(try activeParameterIndex(of: help) == 1)
    }

    @Test
    func lspParameterInfoTestInnerActiveParameterOfTheFirstSignatureIsUsedIfActiveSignatureIsOmitted() throws {
        let help = Fixtures.help([
            Fixtures.signature("a", "b", activeParameter: 1),
            Fixtures.signature("a", "b", "c", activeParameter: 2)
        ])

        #expect(try activeParameterIndex(of: help) == 1)
    }

    @Test
    func lspParameterInfoTestOutOfRangeActiveSignatureDefaultsToTheFirstOne() throws {
        let help = Fixtures.help(
            [
                Fixtures.signature("a", "b", activeParameter: 1),
                Fixtures.signature("a", "b", "c", activeParameter: 2)
            ],
            activeSignature: 5
        )
        let presentation = try #require(SignatureHelpPresentation(help: help))

        #expect(presentation.activeIndex == 0)
        #expect(try activeParameterIndex(of: help) == 1)
    }

    @Test
    func lspParameterInfoTestOutOfRangeOuterActiveParameterDefaultsToZero() throws {
        let help = Fixtures.help([Fixtures.signature("a", "b")], activeParameter: 2)

        #expect(try activeParameterIndex(of: help) == 0)
    }

    @Test
    func lspParameterInfoTestNoActiveParameterIfInnerActiveParameterIsOutOfRange() throws {
        let help = Fixtures.help([Fixtures.signature("a", "b", activeParameter: 2)], activeParameter: 1)

        #expect(try activeParameterIndex(of: help) == -1)
    }

    @Test
    func lspParameterInfoTestNoActiveParameterIfBothActiveParametersAreNull() throws {
        let help = Fixtures.help([Fixtures.signature("a", "b")])
        let presentation = try #require(SignatureHelpPresentation(help: help))

        #expect(try activeParameterIndex(of: help) == -1)
        #expect(presentation.rows[0].segments == [segment("function(a, b)")])
    }

    @Test
    func lspParameterInfoTestActiveParameterIsIgnoredIfTheSignatureHasNoParameters() throws {
        let help = Fixtures.help([Fixtures.signature(activeParameter: 0)], activeParameter: 0)

        #expect(try activeParameterIndex(of: help) == -1)
    }

    @Test
    func signatureWithoutAParametersArrayHasNoActiveParameter() throws {
        let signature = SignatureInformation(label: "run()", parameters: nil, activeParameter: 0)

        #expect(try activeParameterIndex(of: Fixtures.help([signature], activeParameter: 0)) == -1)
    }

    @Test
    func emptyLabelsProduceNoSegments() throws {
        let presentation = try #require(SignatureHelpPresentation(help: Fixtures.help([SignatureInformation(label: "")])))

        #expect(presentation.rows[0].segments.isEmpty)
        #expect(presentation.rows[0].label.isEmpty)
    }

    @Test
    func repeatedParameterTextIsSearchedAfterThePreviousParameter() {
        let signature = SignatureInformation(
            label: "f(a: Int, a: Int)",
            parameters: [
                ParameterInformation(label: .optionA("a: Int")),
                ParameterInformation(label: .optionA("a: Int"))
            ]
        )

        #expect(SignatureHelpLabelRanges.parameterRanges(of: signature) == [2..<8, 10..<16])
    }

    @Test
    func parameterTextBeforeThePreviousParameterFallsBackToTheFirstOccurrence() {
        let signature = SignatureInformation(
            label: "f(a, b)",
            parameters: [ParameterInformation(label: .optionA("b")), ParameterInformation(label: .optionA("a"))]
        )

        #expect(SignatureHelpLabelRanges.parameterRanges(of: signature) == [5..<6, 2..<3])
    }

    @Test
    func missingAndEmptyParameterTextHasNoRange() {
        let signature = SignatureInformation(
            label: "f(a, b)",
            parameters: [ParameterInformation(label: .optionA("zzz")), ParameterInformation(label: .optionA(""))]
        )

        #expect(SignatureHelpLabelRanges.parameterRanges(of: signature) == [nil, nil])
    }

    @Test
    func parameterOffsetsAreValidatedAgainstTheLabelLength() {
        let offsets: [[UInt]] = [[2, 3], [2, 2], [3, 2], [0, 99], [1], [1, 2, 3], [UInt.max, UInt.max]]
        let signature = SignatureInformation(
            label: "f(a, b)",
            parameters: offsets.map { ParameterInformation(label: .optionB($0)) }
        )

        #expect(SignatureHelpLabelRanges.parameterRanges(of: signature) == [2..<3, 2..<2, nil, nil, nil, nil, nil])
    }

    @Test
    func parameterOffsetsAreUtf16UnitsAndSegmentsSplitAtThem() throws {
        let signature = SignatureInformation(
            label: "f(😀: Int, b: Int)",
            parameters: [
                ParameterInformation(label: .optionB([2, 9])),
                ParameterInformation(label: .optionA("b: Int"))
            ],
            activeParameter: 0
        )
        let presentation = try #require(SignatureHelpPresentation(help: Fixtures.help([signature])))

        #expect(presentation.rows[0].segments == [segment("f("), segment("😀: Int", true), segment(", b: Int)")])
    }

    @Test
    func segmentsCoverHighlightsAtTheStartTheEndAndEmptyOnes() {
        #expect(SignatureHelpLabelRanges.segments(label: "abc", highlight: 0..<1) == [segment("a", true), segment("bc")])
        #expect(SignatureHelpLabelRanges.segments(label: "abc", highlight: 2..<3) == [segment("ab"), segment("c", true)])
        #expect(SignatureHelpLabelRanges.segments(label: "abc", highlight: 0..<3) == [segment("abc", true)])
        #expect(SignatureHelpLabelRanges.segments(label: "abc", highlight: 1..<1) == [segment("abc")])
        #expect(SignatureHelpLabelRanges.segments(label: "abc", highlight: nil) == [segment("abc")])
    }

    @Test
    func documentationIsTrimmedTypedAndDroppedWhenBlank() throws {
        #expect(SignatureHelpDocumentation(nil) == nil)
        #expect(SignatureHelpDocumentation(.optionA("  \n")) == nil)
        #expect(SignatureHelpDocumentation(.optionB(MarkupContent(kind: .markdown, value: "")) ) == nil)
        let plain = try #require(SignatureHelpDocumentation(.optionA(" Adds numbers \n")))
        #expect(plain == SignatureHelpDocumentation(.optionB(MarkupContent(kind: .plaintext, value: "Adds numbers"))))
        #expect(!plain.isMarkdown)
        let markdown = try #require(SignatureHelpDocumentation(.optionB(MarkupContent(kind: .markdown, value: "**Adds**"))))
        #expect(markdown.isMarkdown)
        #expect(markdown.text == "**Adds**")
    }

    @Test
    func rowsCarrySignatureAndActiveParameterDocumentation() throws {
        let signature = SignatureInformation(
            label: "f(a, b)",
            documentation: .optionB(MarkupContent(kind: .markdown, value: "Does **things**")),
            parameters: [
                ParameterInformation(label: .optionA("a"), documentation: .optionA("first")),
                ParameterInformation(label: .optionA("b"), documentation: .optionB(MarkupContent(kind: .plaintext, value: "second")))
            ],
            activeParameter: 1
        )
        let row = try #require(SignatureHelpPresentation(help: Fixtures.help([signature])))
            .rows[0]

        #expect(row.documentation?.text == "Does **things**")
        #expect(row.documentation?.isMarkdown == true)
        #expect(row.parameterDocumentation?.text == "second")
        #expect(row.parameterDocumentation?.isMarkdown == false)
    }

    @Test
    func rowsWithoutADocumentedActiveParameterHaveNoParameterDocumentation() throws {
        let presentation = try #require(SignatureHelpPresentation(help: Fixtures.oneOverload(activeParameter: 5)))

        #expect(presentation.rows[0].parameterDocumentation == nil)
        #expect(presentation.rows[0].documentation == nil)
    }

    @Test
    func presentationNeedsAtLeastOneSignature() {
        #expect(SignatureHelpPresentation(help: SignatureHelp(signatures: [])) == nil)
    }

    @Test
    func presentationStartsAtTheServersActiveSignature() throws {
        let overloads = Fixtures.twoOverloads(activeSignature: 1, activeParameter: 2)
        let presentation = try #require(SignatureHelpPresentation(help: overloads))

        #expect(presentation.activeIndex == 1)
        #expect(presentation.rows.map(\.activeParameterIndex) == [0, 2])
        #expect(try #require(SignatureHelpPresentation(help: Fixtures.twoOverloads(activeSignature: nil))).activeIndex == 0)
        #expect(try #require(SignatureHelpPresentation(help: Fixtures.twoOverloads(activeSignature: -1))).activeIndex == 0)
    }

    @Test
    func cyclingWrapsInBothDirectionsAndTracksTheActiveSignatureHelp() throws {
        let presentation = try #require(SignatureHelpPresentation(help: Fixtures.twoOverloads(activeParameter: 1)))
        let next = presentation.cycled(by: 1)
        let wrapped = next.cycled(by: 1)
        let previous = presentation.cycled(by: -1)
        let far = presentation.cycled(by: -5)

        let indices: [Int] = [next.activeIndex, wrapped.activeIndex, previous.activeIndex, far.activeIndex]
        #expect(indices == [1, 0, 1, 1])
        #expect(next.rows == presentation.rows)
        #expect(next.activeSignatureHelp == SignatureHelp(
            signatures: presentation.help.signatures,
            activeSignature: 1,
            activeParameter: 1
        ))
    }

    @Test
    func requestParamsEncodeTheContextAsProtocolJson() throws {
        let active = Fixtures.oneOverload()
        let params = SignatureHelpRequestParams(
            textDocument: TextDocumentIdentifier(uri: "file:///tmp/a.swift"),
            position: Position(line: 3, character: 7),
            context: .typed("(", activeSignatureHelp: active)
        )
        let json = try params.lspAny()

        guard case let .hash(root) = json, case let .hash(context)? = root["context"] else {
            Issue.record("params are not a JSON object")
            return
        }
        #expect(root["textDocument"] == ["uri": "file:///tmp/a.swift"])
        #expect(root["position"] == ["line": 3, "character": 7])
        #expect(context["triggerKind"] == 2)
        #expect(context["triggerCharacter"] == "(")
        #expect(context["isRetrigger"] == true)
        #expect(context["activeSignatureHelp"] != nil)
        #expect(try JSONDecoder().decode(SignatureHelpRequestParams.self, from: JSONEncoder().encode(json)) == params)
    }

    @Test
    func contextsDescribeInvokedTypedAndContentChangeTriggers() {
        let active = Fixtures.oneOverload()

        #expect(SignatureHelpContext.invoked(activeSignatureHelp: nil) == SignatureHelpContext(
            triggerKind: .invoked,
            triggerCharacter: nil,
            isRetrigger: false,
            activeSignatureHelp: nil
        ))
        #expect(SignatureHelpContext.invoked(activeSignatureHelp: active).isRetrigger)
        #expect(SignatureHelpContext.typed(",", activeSignatureHelp: nil) == SignatureHelpContext(
            triggerKind: .triggerCharacter,
            triggerCharacter: ",",
            isRetrigger: false,
            activeSignatureHelp: nil
        ))
        #expect(SignatureHelpContext.contentChange(activeSignatureHelp: active) == SignatureHelpContext(
            triggerKind: .contentChange,
            triggerCharacter: nil,
            isRetrigger: true,
            activeSignatureHelp: active
        ))
        #expect(
            [SignatureHelpTriggerKind.invoked, .triggerCharacter, .contentChange].map(\.rawValue) == [1, 2, 3]
        )
    }
}
