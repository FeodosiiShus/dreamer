import Testing
@testable import Dreamder

@Suite
struct PreserveCaseTests {
    private struct Case {
        let first: String
        let second: String
        let expected: String
    }

    private static let replaceWithCaseRespectCases: [Case] = [
        Case(first: "foo", second: "Bar", expected: "Foo"),
        Case(first: "foo", second: "bar", expected: "foo"),
        Case(first: "foo", second: "BAR", expected: "FOO"),
        Case(first: "Foo", second: "Bar", expected: "Foo"),
        Case(first: "Foo", second: "bar", expected: "foo"),
        Case(first: "Foo", second: "BAR", expected: "FOO"),
        Case(first: "FOO", second: "Bar", expected: "Foo"),
        Case(first: "FOO", second: "bar", expected: "foo"),
        Case(first: "FOO", second: "BAR", expected: "FOO"),
        Case(first: "fooBar", second: "Bar", expected: "FooBar"),
        Case(first: "fooBar", second: "bar", expected: "fooBar"),
        Case(first: "DEF1", second: "abc1", expected: "def1"),
        Case(first: "DEF1", second: "Abc1", expected: "Def1"),
        Case(first: "DEF1", second: "ABC1", expected: "DEF1"),
        Case(first: "abc", second: "a1", expected: "abc"),
        Case(first: "abc", second: "A1", expected: "ABC"),
        Case(first: "Report", second: "display preferences", expected: "report"),
        Case(first: "Report", second: "DISPLAY PREFERENCES", expected: "REPORT"),
        Case(first: "Report", second: "display Preferences", expected: "report"),
        Case(first: "Report", second: "Display preferences", expected: "Report"),
        Case(first: "MyTest", second: "USERCODE", expected: "MYTEST"),
        Case(first: "MyTest", second: "UserCode", expected: "MyTest"),
        Case(first: "MyTest", second: "userCode", expected: "myTest")
    ]

    private static let applyCaseCases: [Case] = [
        Case(first: "Bar", second: "foo", expected: "Foo"),
        Case(first: "bar", second: "foo", expected: "foo"),
        Case(first: "BAR", second: "foo", expected: "FOO"),
        Case(first: "Bar", second: "Foo", expected: "Foo"),
        Case(first: "bar", second: "Foo", expected: "foo"),
        Case(first: "BAR", second: "Foo", expected: "FOO"),
        Case(first: "Bar", second: "FOO", expected: "Foo"),
        Case(first: "bar", second: "FOO", expected: "foo"),
        Case(first: "BAR", second: "FOO", expected: "FOO"),
        Case(first: "Bar", second: "fooBar", expected: "FooBar"),
        Case(first: "bar", second: "fooBar", expected: "fooBar"),
        Case(first: "abc1", second: "DEF1", expected: "def1"),
        Case(first: "Abc1", second: "DEF1", expected: "Def1"),
        Case(first: "ABC1", second: "DEF1", expected: "DEF1"),
        Case(first: "a1", second: "abc", expected: "abc"),
        Case(first: "A1", second: "abc", expected: "ABC"),
        Case(first: "display preferences", second: "Report", expected: "report"),
        Case(first: "DISPLAY PREFERENCES", second: "Report", expected: "REPORT"),
        Case(first: "display Preferences", second: "Report", expected: "report"),
        Case(first: "Display preferences", second: "Report", expected: "Report"),
        Case(first: "USERCODE", second: "MyTest", expected: "MYTEST"),
        Case(first: "UserCode", second: "MyTest", expected: "MyTest"),
        Case(first: "userCode", second: "MyTest", expected: "myTest")
    ]

    private static let applyCaseWordCases: [Case] = [
        Case(first: "report", second: "display preferences", expected: "display preferences"),
        Case(first: "REPORT", second: "display preferences", expected: "DISPLAY PREFERENCES"),
        Case(first: "Report", second: "display preferences", expected: "Display Preferences"),
        Case(first: "Project_Lead_Id", second: "PROGRAM_LEAD_ID", expected: "Program_Lead_Id"),
        Case(first: "niceWeather", second: "SUN_SHINE", expected: "sun_shine"),
        Case(first: "niceweather", second: "SUN_SHINE", expected: "sun_shine"),
        Case(first: "111", second: "do nothing", expected: "do nothing"),
        Case(first: "111", second: "Do Nothing", expected: "Do Nothing"),
        Case(first: "111", second: "DO NOTHING", expected: "DO NOTHING"),
        Case(first: "111", second: "222", expected: "222"),
        Case(first: "Test_String", second: "string_test", expected: "String_Test"),
        Case(first: "Case", second: "_case", expected: "_Case"),
        Case(first: "control.search", second: "control.SearchControl", expected: "control.searchControl"),
        Case(first: "control.Search", second: "control.SearchControl", expected: "control.SearchControl")
    ]

    @Test
    func replaceWithCaseRespectMatchesIntelliJCases() {
        for item in Self.replaceWithCaseRespectCases {
            let actual = PreserveCase.replaceWithCaseRespect(item.first, foundString: item.second)
            #expect(actual == item.expected, "toReplace=\(item.first) found=\(item.second)")
        }
    }

    @Test
    func applyCaseMatchesIntelliJCasesSharedWithReplaceWithCaseRespect() {
        for item in Self.applyCaseCases {
            let actual = PreserveCase.applyCase(found: item.first, replacement: item.second)
            #expect(actual == item.expected, "found=\(item.first) replacement=\(item.second)")
        }
    }

    @Test
    func applyCaseAppliesCasePerWord() {
        for item in Self.applyCaseWordCases {
            let actual = PreserveCase.applyCase(found: item.first, replacement: item.second)
            #expect(actual == item.expected, "found=\(item.first) replacement=\(item.second)")
        }
    }

    @Test
    func emptyInputsReturnTheReplacementUnchanged() {
        #expect(PreserveCase.replaceWithCaseRespect("", foundString: "Bar").isEmpty)
        #expect(PreserveCase.replaceWithCaseRespect("foo", foundString: "") == "foo")
        #expect(PreserveCase.applyCase(found: "", replacement: "foo") == "foo")
        #expect(PreserveCase.applyCase(found: "Bar", replacement: "").isEmpty)
    }

    @Test
    func singleCharacterReplacementFollowsTheFirstFoundCharacter() {
        #expect(PreserveCase.replaceWithCaseRespect("b", foundString: "Foo") == "B")
        #expect(PreserveCase.replaceWithCaseRespect("b", foundString: "foo") == "b")
    }

    @Test
    func singleCharacterMatchCapitalizesOnlyTheFirstReplacementCharacter() {
        #expect(PreserveCase.replaceWithCaseRespect("bar", foundString: "F") == "Bar")
        #expect(PreserveCase.replaceWithCaseRespect("bar", foundString: "f") == "bar")
    }

    @Test
    func foundTailWithoutLettersFallsBackToTheFirstCharacterCase() {
        #expect(PreserveCase.replaceWithCaseRespect("bar", foundString: "A1") == "BAR")
        #expect(PreserveCase.replaceWithCaseRespect("Bar", foundString: "a1") == "bar")
        #expect(PreserveCase.replaceWithCaseRespect("bar", foundString: "11") == "bar")
    }

    @Test
    func mixedCaseFoundTailKeepsTheReplacementTail() {
        #expect(PreserveCase.replaceWithCaseRespect("Bar", foundString: "fOoBar") == "bar")
    }

    @Test
    func foundTextWithoutWordCharactersLeavesTheReplacementUnchanged() {
        #expect(PreserveCase.applyCase(found: "--", replacement: "foo") == "foo")
    }

    @Test
    func charactersWithoutASingleCharacterCaseMappingKeepTheirCase() {
        #expect(PreserveCase.replaceWithCaseRespect("\u{DF}ar", foundString: "FOO") == "\u{DF}AR")
        #expect(PreserveCase.replaceWithCaseRespect("\u{DF}ar", foundString: "foo") == "\u{DF}ar")
    }
}
