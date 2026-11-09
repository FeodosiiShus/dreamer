import Testing
import Foundation
@testable import Dreamder

@Suite
struct RegistryItemTemplateParserTests {
    private func render(_ template: String, _ context: [String: Any] = [:]) throws -> String {
        try RegistryItemTemplateParser.process(template: template, with: context)
    }

    private func failure(_ template: String, _ context: [String: Any] = [:]) -> String? {
        do {
            _ = try RegistryItemTemplateParser.process(template: template, with: context)
            return nil
        } catch let error as RegistryItemTemplateParser.TemplateError {
            switch error {
            case .invalidFilter(let value): return "invalidFilter:\(value)"
            case .missingVariable(let value): return "missingVariable:\(value)"
            case .invalidPath(let value): return "invalidPath:\(value)"
            case .missingKey(let value): return "missingKey:\(value)"
            }
        } catch {
            return "other:\(error)"
        }
    }

    @Test
    func literalTemplatesPassThroughUnchanged() throws {
        #expect(try render("actionlint_linux_amd64.tar.gz") == "actionlint_linux_amd64.tar.gz")
        #expect(try render("") == "")
        #expect(try render("single { brace } and $dollar") == "single { brace } and $dollar")
    }

    @Test
    func variableIsReplacedByItsContextValue() throws {
        #expect(try render("{{ version }}", ["version": "1.2.3"]) == "1.2.3")
        #expect(try render("tool-{{ version }}.zip", ["version": "1.2.3"]) == "tool-1.2.3.zip")
    }

    @Test
    func whitespaceAroundTheExpressionIsOptional() throws {
        let context: [String: Any] = ["version": "9"]
        #expect(try render("{{version}}", context) == "9")
        #expect(try render("{{   version   }}", context) == "9")
        #expect(try render("{{\tversion\t}}", context) == "9")
    }

    @Test
    func dotPathsTraverseNestedDictionariesAndArrays() throws {
        let context: [String: Any] = [
            "source": ["id": "pkg:github/acme/tool@v1"] as [String: Any],
            "assets": [["file": "a.zip"], ["file": "b.zip"]] as [Any],
            "names": ["x", "y", "z"]
        ]
        #expect(try render("{{ source.id }}", context) == "pkg:github/acme/tool@v1")
        #expect(try render("{{ assets.1.file }}", context) == "b.zip")
        #expect(try render("{{ names.0 }}{{ names.2 }}", context) == "xz")
    }

    @Test
    func scalarValuesAreStringified() throws {
        let context: [String: Any] = ["count": 3, "ratio": 1.5, "flag": true, "text": "t"]
        #expect(try render("{{ count }}|{{ ratio }}|{{ flag }}|{{ text }}", context) == "3|1.5|true|t")
    }

    @Test
    func stripPrefixRemovesAMatchingPrefixOnly() throws {
        #expect(try render("{{ version | strip_prefix \"v\" }}", ["version": "v0.53.0"]) == "0.53.0")
        #expect(try render("{{ version | strip_prefix \"v\" }}", ["version": "0.53.0"]) == "0.53.0")
        #expect(try render("{{ version | strip_prefix \"release-\" }}", ["version": "release-2.0"]) == "2.0")
        #expect(try render("{{ version | strip_prefix \"\" }}", ["version": "v1"]) == "v1")
    }

    @Test
    func filtersAreAppliedLeftToRight() throws {
        let template = "{{ version | strip_prefix \"v\" | strip_prefix \"0.\" }}"
        #expect(try render(template, ["version": "v0.53.0"]) == "53.0")
    }

    @Test
    func registryExampleFromTheDocumentationRenders() throws {
        let template = "protolint_{{ version | strip_prefix \"v\" }}_darwin_arm64.tar.gz"
        #expect(try render(template, ["version": "v0.53.0"]) == "protolint_0.53.0_darwin_arm64.tar.gz")
    }

    @Test
    func multipleAndAdjacentExpressionsAreAllReplaced() throws {
        let context: [String: Any] = ["name": "tool", "version": "v10.20.30", "os": "darwin"]
        #expect(try render("{{ name }}-{{ version }}-{{ os }}", context) == "tool-v10.20.30-darwin")
        #expect(try render("{{name}}{{version}}", context) == "toolv10.20.30")
        #expect(try render("{{ name }}/{{ name }}", context) == "tool/tool")
    }

    @Test
    func replacementValuesAreNotRescannedForExpressions() throws {
        #expect(try render("{{ a }}", ["a": "{{ b }}", "b": "x"]) == "{{ b }}")
    }

    @Test
    func multibyteTextAroundExpressionsIsPreserved() throws {
        #expect(try render("→{{ version }}←🙂{{ version }}", ["version": "1.0"]) == "→1.0←🙂1.0")
    }

    @Test
    func unterminatedOrMalformedDelimitersAreLeftAsText() throws {
        let context: [String: Any] = ["version": "1"]
        #expect(try render("tool_{{ version", context) == "tool_{{ version")
        #expect(try render("tool_{ version }}", context) == "tool_{ version }}")
        #expect(try render("{{}}", context) == "{{}}")
        #expect(try render("{{ version }} and {{ version", context) == "1 and {{ version")
    }

    @Test
    func missingKeyNamesTheFirstUnresolvedComponent() {
        #expect(failure("{{ nope }}", ["version": "1"]) == "missingKey:nope")
        #expect(failure("{{ source.missing }}", ["source": ["id": "x"] as [String: Any]]) == "missingKey:missing")
        #expect(failure("{{ }}") == "missingKey:")
    }

    @Test
    func invalidPathsDescribeWhatWentWrong() {
        let context: [String: Any] = [
            "version": "1",
            "items": ["a", "b"],
            "source": ["id": "x"] as [String: Any]
        ]
        #expect(failure("{{ version.major }}", context) == "invalidPath:Cannot access component: major")
        #expect(failure("{{ items.2 }}", context) == "invalidPath:Array index out of bounds: 2")
        #expect(failure("{{ items.-1 }}", context) == "invalidPath:Array index out of bounds: -1")
        #expect(failure("{{ items.first }}", context) == "invalidPath:Cannot access component: first")
        #expect(
            failure("{{ source }}", context)
                == "invalidPath:Path resolves to a complex object, not a simple value"
        )
        #expect(
            failure("{{ items }}", context)
                == "invalidPath:Path resolves to a complex object, not a simple value"
        )
    }

    @Test
    func unsupportedOrMalformedFiltersAreRejected() {
        let context: [String: Any] = ["version": "v1"]
        #expect(failure("{{ version | upcase }}", context) == "invalidFilter:upcase")
        #expect(failure("{{ version | strip_prefix v }}", context) == "invalidFilter:strip_prefix v")
        #expect(failure("{{ version | strip_prefix }}", context) == "invalidFilter:strip_prefix")
    }

    @Test
    func aFailingExpressionFailsTheWholeTemplate() {
        #expect(failure("ok_{{ version }}_{{ nope }}", ["version": "1"]) == "missingKey:nope")
    }

    @Test
    func expressionsWithOnlyPipeSeparatorsFailInsteadOfTrapping() {
        #expect(failure("{{||}}") == "invalidPath:Empty expression")
    }

    @Test
    func aLeadingPipeLeavesAnEmptyVariablePath() {
        #expect(failure("{{ | strip_prefix \"x\" }}", ["version": "v1"]) == "missingKey:")
    }

    @Test
    func valuesOfOtherTypesFallBackToTheirDescription() throws {
        struct Opaque: CustomStringConvertible {
            var description: String { "opaque-value" }
        }
        #expect(try render("tool-{{ marker }}", ["marker": Opaque()]) == "tool-opaque-value")
    }
}
