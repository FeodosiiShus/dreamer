import Foundation
import Testing
@testable import Dreamder

@Suite
struct RegexReplacementTests {
    private func replace(pattern: String, in text: String, with template: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let match = try #require(regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)))
        return try RegexReplacement.createReplacement(template: template, match: match, in: nsText, regex: regex)
    }

    private func message(pattern: String, template: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        do throws(RegexReplacement.TemplateError) {
            try RegexReplacement.validate(template: template, regex: regex)
            return nil
        } catch {
            return error.message
        }
    }

    @Test
    func numberedGroupsAreSubstituted() throws {
        #expect(try replace(pattern: "(\\w+)@(\\w+)", in: "john@example", with: "$2/$1") == "example/john")
        #expect(try replace(pattern: "(\\w+)@(\\w+)", in: "john@example", with: "[$0]") == "[john@example]")
    }

    @Test
    func namedGroupsAreSubstituted() throws {
        let result = try replace(
            pattern: "(?<user>\\w+)@(?<host>\\w+)",
            in: "john@example",
            with: "${host}:${user}"
        )
        #expect(result == "example:john")
    }

    @Test
    func largestLegalGroupNumberIsUsed() throws {
        let pattern = "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"
        #expect(try replace(pattern: pattern, in: "abcdefghij", with: "$10") == "j")
        #expect(try replace(pattern: "(a)", in: "a", with: "$10") == "a0")
    }

    @Test
    func nonParticipatingGroupsProduceNothing() throws {
        #expect(try replace(pattern: "(a)|(b)", in: "b", with: "<$1|$2>") == "<|b>")
    }

    @Test
    func controlCharactersAreExpanded() throws {
        #expect(try replace(pattern: "x", in: "x", with: "a\\nb\\tc\\rd") == "a\nb\tc\rd")
        #expect(try replace(pattern: "x", in: "x", with: "\\x0041\\\\\\$") == "A\\$")
        #expect(try replace(pattern: "x", in: "x", with: "\\xZZZZ") == "ZZZZ")
    }

    @Test
    func caseConversionOfASingleCharacter() throws {
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "\\u$1") == "John")
        #expect(try replace(pattern: "(\\w+)", in: "JOHN", with: "\\l$1") == "jOHN")
    }

    @Test
    func caseConversionOfARegion() throws {
        #expect(try replace(pattern: "(\\w+)@(\\w+)", in: "john@example", with: "\\U$1\\E-$2") == "JOHN-example")
        #expect(try replace(pattern: "(\\w+)@(\\w+)", in: "JOHN@EXAMPLE", with: "\\L$1@\\U$2") == "john@EXAMPLE")
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "\\Uab\\Lcd") == "ABcd")
    }

    @Test
    func unterminatedRegionConvertsToTheEnd() throws {
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "x\\U$1!") == "xJOHN!")
    }

    @Test
    func characterConversionInsideARegionIsIgnored() throws {
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "\\U\\l$1") == "JOHN")
    }

    @Test
    func emptyRegionIsDropped() throws {
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "\\U\\E$1") == "john")
    }

    @Test
    func trailingBackslashIsRejected() throws {
        #expect(try message(pattern: "a", template: "x\\") == "character to be escaped is missing")
    }

    @Test
    func trailingDollarIsRejected() throws {
        let detail = try message(pattern: "a", template: "x$")
        #expect(detail == "Illegal group reference: group index is missing")
    }

    @Test
    func malformedNamedGroupReferencesAreRejected() throws {
        #expect(try message(pattern: "(?<a>x)", template: "${}") == "named capturing group has 0 length name")
        #expect(try message(pattern: "(?<a>x)", template: "${a") == "named capturing group is missing trailing '}'")
        #expect(
            try message(pattern: "(?<a>x)", template: "${1a}") == "capturing group name {1a} starts with digit character"
        )
    }

    @Test
    func unknownGroupsAreRejected() throws {
        #expect(try message(pattern: "(a)", template: "$2") == "No group 2")
        #expect(try message(pattern: "(a)", template: "${missing}") == "No group with name <missing>")
        #expect(try message(pattern: "(a)", template: "$x") == "Illegal group reference")
    }

    @Test
    func validTemplatesPassValidation() throws {
        #expect(try message(pattern: "(?<a>x)(y)", template: "${a}-$1-$2-\\U$0\\E") == nil)
    }

    @Test
    func captureGroupNamesSkipEscapesClassesAndLookbehinds() {
        let pattern = "(?<first>a)\\(?<no>x\\)[(?<in>)](?<=b)(?<!c)\\Q(?<q>\\E(?<second>d)"
        #expect(RegexReplacement.captureGroupNames(in: pattern) == ["first", "second"])
    }

    @Test
    func caseResetWithoutAnOpenConversionIsIgnored() throws {
        #expect(try replace(pattern: "x", in: "x", with: "a\\Eb") == "ab")
    }

    @Test
    func incompleteOrInvalidHexadecimalEscapesAreHandled() throws {
        #expect(try replace(pattern: "x", in: "x", with: "\\x00") == "00")
        #expect(try replace(pattern: "x", in: "x", with: "\\xD800") == "\u{FFFD}")
    }

    @Test
    func repeatedRegionOfTheSameCaseExtendsTheOpenRegion() throws {
        #expect(try replace(pattern: "x", in: "x", with: "\\Ua\\Ub") == "AB")
    }

    @Test
    func regionOfTheOppositeCaseAtTheSameOffsetReplacesTheOpenOne() throws {
        #expect(try replace(pattern: "(\\w+)", in: "JOHN", with: "\\U\\L$1") == "john")
    }

    @Test
    func unterminatedQuotedSectionHidesGroupNamesUntilTheEnd() {
        #expect(RegexReplacement.captureGroupNames(in: "\\Q(?<a>x)").isEmpty)
    }

    @Test
    func backspaceAndFormFeedEscapesExpandToTheirControlCharacters() throws {
        #expect(try replace(pattern: "x", in: "x", with: "a\\bb\\fc") == "a\u{08}b\u{0C}c")
    }

    @Test
    func consecutiveSingleCharacterConversionsApplyOnlyOnceTheFirstOneIsClosed() throws {
        #expect(try replace(pattern: "x", in: "x", with: "\\ua\\ub") == "AB")
        #expect(try replace(pattern: "x", in: "x", with: "\\la\\ub") == "aB")
        #expect(try replace(pattern: "x", in: "x", with: "\\u\\lab") == "Ab")
    }

    @Test
    func nonAsciiDigitsAreNeitherGroupNumbersNorGroupNames() throws {
        #expect(try message(pattern: "(a)", template: "$\u{0663}") == "Illegal group reference")
        #expect(try message(pattern: "(?<a>x)", template: "${\u{0663}}") == "named capturing group has 0 length name")
    }
}
