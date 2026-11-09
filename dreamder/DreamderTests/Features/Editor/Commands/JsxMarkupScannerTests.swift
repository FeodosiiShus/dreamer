import Foundation
import Testing
@testable import Dreamder

struct JsxMarkupScannerTests {
    private func markup(_ source: String) -> [String] {
        let units = Array(source.utf16)
        return JsxMarkupScanner(units: units).markupRanges.map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test
    func selfClosingElementIsMarkup() {
        #expect(markup("x = <a/>;") == ["<a/>"])
    }

    @Test
    func nestedElementsFormOneRange() {
        #expect(markup("x = <div><span>t</span></div>;") == ["<div><span>t</span></div>"])
    }

    @Test
    func fragmentsAreMarkup() {
        #expect(markup("y = <><b>t</b></>;") == ["<><b>t</b></>"])
    }

    @Test
    func quotedAttributesMayContainAngleBrackets() {
        #expect(markup("x = <a b=\"1>2\" c='3'>t</a>;") == ["<a b=\"1>2\" c='3'>t</a>"])
    }

    @Test
    func unterminatedAttributeStringExtendsToTheEndOfTheSource() {
        #expect(markup("x = <a b=\"oops") == ["<a b=\"oops"])
    }

    @Test
    func expressionContainersSplitTheRange() {
        #expect(markup("x = <a b={y} c={{d: 1}}>t {e} u</a>;") == ["<a b={", " c={", ">t {", " u</a>"])
    }

    @Test
    func elementsInsideChildExpressionsAreSeparateRanges() {
        #expect(markup("x = <ul>{ok && <li/>}</ul>;") == ["<ul>{", "<li/>", "}</ul>"])
    }

    @Test
    func elementsInsideAttributeExpressionsResumeTheOuterTag() {
        #expect(markup("x = <a b={<c d={e}/>}/>;") == ["<a b={", "<c d={", "/>", "/>"])
    }

    @Test
    func expressionInsideAClosingTagDoesNotResumeMarkup() {
        #expect(markup("x = <a></a {y}>z;") == ["<a></a {"])
    }

    @Test
    func expressionAtTheEndOfTheSourceLeavesNoEmptyRange() {
        #expect(markup("x = <a>{y}") == ["<a>{"])
    }

    @Test
    func unterminatedElementExtendsToTheEndOfTheSource() {
        #expect(markup("x = <a>t") == ["<a>t"])
    }

    @Test
    func lessThanSignInChildTextIsNotAnElement() {
        #expect(markup("x = <p>a < 3</p>;") == ["<p>a < 3</p>"])
    }

    @Test
    func templateLiteralsHideAndExposeExpressions() {
        #expect(markup("t = `a ${ <b/> } \\` ${c} `; u = <d/>;") == ["<b/>", "<d/>"])
    }

    @Test
    func lineCommentsEndAtCarriageReturn() {
        #expect(markup("// <a/>\r<b/>x = <c/>;") == ["<b/>", "<c/>"])
    }

    @Test
    func unterminatedLineCommentHidesTheRest() {
        #expect(markup("// <a/>") == [])
    }

    @Test
    func blockCommentsHideElements() {
        #expect(markup("/* <a/> * */ x = <b/>; /* <c/>") == ["<b/>"])
    }

    @Test
    func stringsHideElementsAndHonorEscapes() {
        #expect(markup("x = 'it\\'s <a/>'; y = \"q\"; z = <b/>;") == ["<b/>"])
    }

    @Test
    func singleLineStringEndsAtTheLineBreak() {
        #expect(markup("x = 'abc\ny = <h/>;") == ["<h/>"])
    }

    @Test
    func unterminatedStringHidesTheRest() {
        #expect(markup("x = 'abc <a/>") == [])
    }

    @Test
    func trailingBackslashInAStringEndsTheScan() {
        #expect(markup("x = 'ab\\") == [])
    }

    @Test
    func bracesTrackDepthAndIgnoreStrayClosers() {
        #expect(markup("if (a) { b = {c: 1}; } d = <e/>; }") == ["<e/>"])
    }

    @Test
    func closingParenthesisAndBracketForbidAnElementStart() {
        #expect(markup("f(a) <b>c</b>; v[1] <d>e</d>;") == [])
    }

    @Test
    func expressionKeywordsAllowAnElementStart() {
        #expect(markup("return <a/>; yield <b/>; foo <c/>;") == ["<a/>", "<b/>"])
    }

    @Test
    func identifierStartCharactersOpenElements() {
        #expect(markup("x = <_a/>; y = <$b/>; z = <C/>; w = <d1/>;") == ["<_a/>", "<$b/>", "<C/>", "<d1/>"])
    }

    @Test
    func nonAsciiIdentifiersDoNotBreakWordScanning() {
        #expect(markup("na\u{EF}ve1 = <a/>;") == ["<a/>"])
    }

    @Test
    func lessThanWithoutAnIdentifierIsAnOperator() {
        #expect(markup("x = < 3; y = a < b; z = <") == [])
    }

    @Test
    func isMarkupFindsOffsetsInsideAndOutsideRanges() {
        let scanner = JsxMarkupScanner(units: Array("a = <b/>; c = <d/>;".utf16))
        #expect(scanner.markupRanges == [4..<8, 14..<18])
        #expect(!scanner.isMarkup(at: 0))
        #expect(!scanner.isMarkup(at: 3))
        #expect(scanner.isMarkup(at: 4))
        #expect(scanner.isMarkup(at: 7))
        #expect(!scanner.isMarkup(at: 8))
        #expect(!scanner.isMarkup(at: 10))
        #expect(!scanner.isMarkup(at: 13))
        #expect(scanner.isMarkup(at: 14))
        #expect(scanner.isMarkup(at: 17))
        #expect(!scanner.isMarkup(at: 18))
        #expect(!scanner.isMarkup(at: 100))
    }

    @Test
    func emptySourceHasNoMarkup() {
        let scanner = JsxMarkupScanner(units: [])
        #expect(scanner.markupRanges.isEmpty)
        #expect(!scanner.isMarkup(at: 0))
    }
}
