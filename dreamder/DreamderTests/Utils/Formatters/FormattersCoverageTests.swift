import Foundation
import Testing
@testable import Dreamder

@Suite
struct RegexFormatterCoverageTests {
    private let identifierFormatter = RegexFormatter(pattern: "[^a-zA-Z0-9_-]")

    @Test
    func stringForRemovesMatchesWithTheEmptyTemplate() {
        #expect(identifierFormatter.string(for: "feature/new branch!") == "featurenewbranch")
        #expect(identifierFormatter.string(for: "clean_name-1") == "clean_name-1")
    }

    @Test
    func stringForAppliesTheReplacementTemplate() {
        let formatter = RegexFormatter(pattern: "\\s+", replacementTemplate: "-")

        #expect(formatter.string(for: "a b   c") == "a-b-c")
        #expect(formatter.replacementTemplate == "-")
    }

    @Test
    func stringForRejectsNonStringObjects() {
        #expect(identifierFormatter.string(for: 42) == nil)
        #expect(identifierFormatter.string(for: nil) == nil)
    }

    @Test
    func getObjectValueReturnsTheFormattedString() {
        var object: AnyObject?
        var message: NSString?

        let accepted = identifierFormatter.getObjectValue(&object, for: "x y/z", errorDescription: &message)

        #expect(accepted)
        #expect(object as? String == "xyz")
        #expect(message == nil)
    }

    @Test
    func getObjectValueToleratesMissingOutputPointers() {
        #expect(identifierFormatter.getObjectValue(nil, for: "x y", errorDescription: nil))
    }

    @Test
    func partialStringIsRejectedAndReplacedWhenItNeedsFormatting() {
        var edited: NSString?
        var message: NSString?

        let valid = identifierFormatter.isPartialStringValid(
            "ab c",
            newEditingString: &edited,
            errorDescription: &message
        )

        #expect(!valid)
        #expect((edited as String?) == "abc")
    }

    @Test
    func partialStringIsAcceptedWhenAlreadyClean() {
        var edited: NSString?
        var message: NSString?

        let valid = identifierFormatter.isPartialStringValid(
            "ab_c",
            newEditingString: &edited,
            errorDescription: &message
        )

        #expect(valid)
        #expect((edited as String?) == "ab_c")
        #expect(identifierFormatter.isPartialStringValid("ab c", newEditingString: nil, errorDescription: nil) == false)
    }

    @Test
    func invalidPatternLeavesStringsUntouched() {
        let formatter = RegexFormatter(pattern: "(")

        #expect(formatter.regex == nil)
        #expect(formatter.string(for: "a(b") == "a(b")
        var edited: NSString?
        var message: NSString?
        #expect(formatter.isPartialStringValid("a(b", newEditingString: &edited, errorDescription: &message))
    }

    @Test
    func decodingFromACoderIsUnsupported() {
        #expect(RegexFormatter(coder: NSKeyedArchiver(requiringSecureCoding: false)) == nil)
    }
}

@Suite
struct TrimWhitespaceFormatterCoverageTests {
    private let formatter = TrimWhitespaceFormatter()

    @Test
    func stringForTrimsWhitespaceAndNewlines() {
        #expect(formatter.string(for: "  https://example.com/repo.git \n") == "https://example.com/repo.git")
        #expect(formatter.string(for: "a b") == "a b")
    }

    @Test
    func stringForRejectsNonStringObjects() {
        #expect(formatter.string(for: 3.5) == nil)
        #expect(formatter.string(for: nil) == nil)
    }

    @Test
    func getObjectValueReturnsTheTrimmedString() {
        var object: AnyObject?
        var message: NSString?

        let accepted = formatter.getObjectValue(&object, for: "\t value \n", errorDescription: &message)

        #expect(accepted)
        #expect(object as? String == "value")
    }

    @Test
    func getObjectValueToleratesAMissingOutputPointer() {
        #expect(formatter.getObjectValue(nil, for: " x ", errorDescription: nil))
    }

    @Test
    func partialStringsAreAlwaysAcceptedAndOfferedTrimmed() {
        var edited: NSString?
        var message: NSString?

        let valid = formatter.isPartialStringValid(
            "  padded  ",
            newEditingString: &edited,
            errorDescription: &message
        )

        #expect(valid)
        #expect((edited as String?) == "padded")
        #expect(formatter.isPartialStringValid(" x", newEditingString: nil, errorDescription: nil))
    }
}
