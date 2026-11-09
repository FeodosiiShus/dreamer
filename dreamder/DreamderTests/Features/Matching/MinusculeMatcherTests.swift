import Testing
@testable import Dreamder

private func makeMatcher(
    _ pattern: String,
    _ mode: MatchingCaseMode = .ignoreCase,
    hardSeparators: String = ""
) -> MinusculeMatcher {
    MinusculeMatcher(pattern: pattern, mode: mode, hardSeparators: hardSeparators)
}

private func expectMatches(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(makeMatcher(pattern).matches(name), "\(pattern) doesn't match \(name)", sourceLocation: sourceLocation)
}

private func expectNoMatch(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(!makeMatcher(pattern).matches(name), "\(pattern) matches \(name)", sourceLocation: sourceLocation)
}

private func expectFirstLetterMatches(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        makeMatcher(pattern, .firstLetter).matches(name),
        "first-letter \(pattern) doesn't match \(name)",
        sourceLocation: sourceLocation
    )
}

private func expectFirstLetterNoMatch(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        !makeMatcher(pattern, .firstLetter).matches(name),
        "first-letter \(pattern) matches \(name)",
        sourceLocation: sourceLocation
    )
}

private func expectCaseSensitiveMatches(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        makeMatcher(pattern, .matchCase).matches(name),
        "case-sensitive \(pattern) doesn't match \(name)",
        sourceLocation: sourceLocation
    )
}

private func expectCaseSensitiveNoMatch(
    _ pattern: String,
    _ name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        !makeMatcher(pattern, .matchCase).matches(name),
        "case-sensitive \(pattern) matches \(name)",
        sourceLocation: sourceLocation
    )
}

private func expectPreference(
    _ pattern: String,
    less: String,
    more: String,
    mode: MatchingCaseMode = .firstLetter,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let matcher = makeMatcher(pattern, mode)
    let lessDegree = matcher.matchingDegree(less)
    let moreDegree = matcher.matchingDegree(more)
    #expect(
        lessDegree < moreDegree,
        "\(pattern): \(less)=\(lessDegree) is not below \(more)=\(moreDegree)",
        sourceLocation: sourceLocation
    )
}

private func expectNoPreference(
    _ pattern: String,
    _ first: String,
    _ second: String,
    mode: MatchingCaseMode,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let matcher = makeMatcher(pattern, mode)
    #expect(
        matcher.matchingDegree(first) == matcher.matchingDegree(second),
        "\(pattern): \(first) and \(second) should rank equally",
        sourceLocation: sourceLocation
    )
}

@Suite("MinusculeMatcher camel humps and word starts")
struct MinusculeMatcherCamelHumpTests {
    @Test func simpleCases() {
        expectMatches("N", "NameUtilTest")
        expectMatches("NU", "NameUtilTest")
        expectMatches("NUT", "NameUtilTest")
        expectMatches("NaUT", "NameUtilTest")
        expectNoMatch("NeUT", "NameUtilTest")
        expectNoMatch("NaUTa", "NameUtilTest")
        expectMatches("NaUtT", "NameUtilTest")
        expectMatches("NaUtTe", "NameUtilTest")
        expectMatches("AACl", "AAClass")
        expectMatches("ZZZ", "ZZZZZZZZZZ")
    }

    @Test func emptyPattern() {
        expectMatches("", "")
        expectMatches("", "asdfs")
        #expect(makeMatcher("").match("asdfs") == [])
        #expect(makeMatcher("*").match("asdfs") == [])
    }

    @Test func skipWords() {
        expectMatches("nt", "NameUtilTest")
        expectMatches("repl map", "ReplacePathToMacroMap")
        expectMatches("replmap", "ReplacePathToMacroMap")
        expectMatches("CertificateEx", "CertificateEncodingException")
        expectNoMatch("ABCD", "AbstractButton.DISABLED_ICON_CHANGED_PROPERTY")
        expectMatches("templipa", "template_impl_template_list_panel")
        expectMatches("templistpa", "template_impl_template_list_panel")
    }

    @Test func simpleCasesWithFirstLowercased() {
        expectMatches("N", "nameUtilTest")
        expectNoMatch("N", "anameUtilTest")
        expectMatches("NU", "nameUtilTest")
        expectNoMatch("NU", "anameUtilTest")
        expectMatches("NUT", "nameUtilTest")
        expectMatches("NaUT", "nameUtilTest")
        expectNoMatch("NeUT", "nameUtilTest")
        expectNoMatch("NaUTa", "nameUtilTest")
        expectMatches("NaUtT", "nameUtilTest")
        expectMatches("NaUtTe", "nameUtilTest")
    }

    @Test func underscoreStyle() {
        expectMatches("N_U_T", "NAME_UTIL_TEST")
        expectMatches("NUT", "NAME_UTIL_TEST")
        expectNoMatch("NUT", "NameutilTest")
    }

    @Test func allUppercaseWords() {
        expectMatches("NOS", "NetOutputStream")
    }

    @Test func allCapsAcronymBoundaries() {
        #expect(makeMatcher("HS").match("HTTPServer") == [0..<1, 4..<5])
        #expect(makeMatcher("*Serv").match("HTTPServer") == [4..<8])
        #expect(makeMatcher("HTTPS").match("HTTPServer") == [0..<5])
        #expect(makeMatcher("HTS").match("HTTPServer") == [0..<2, 4..<5])
        expectNoMatch("HTX", "HTTPServer")
    }

    @Test func xmlCompletion() {
        expectNoMatch("N_T", "NameUtilTest")
        expectMatches("ORGS_ACC", "ORGS_POSITION_ACCOUNTABILITY")
        expectMatches("ORGS-ACC", "ORGS-POSITION_ACCOUNTABILITY")
        expectMatches("ORGS.ACC", "ORGS.POSITION_ACCOUNTABILITY")
    }

    @Test func starFalsePositive() {
        expectNoMatch("ar*l*p", "AbstractResponseHandler")
    }

    @Test func lowerCaseWords() {
        expectMatches("uct", "unit_controller_test")
        expectMatches("unictest", "unit_controller_test")
        expectMatches("uc", "unit_controller_test")
        expectNoMatch("nc", "unit_controller_test")
        expectNoMatch("utc", "unit_controller_test")
    }

    @Test func lowerCaseHumps() {
        expectMatches("foo", "foo")
        expectNoMatch("foo", "fxoo")
        expectMatches("foo", "fOo")
        expectMatches("foo", "fxOo")
        expectMatches("foo", "fXOo")
        expectMatches("fOo", "foo")
        expectNoMatch("fOo", "FaOaOaXXXX")
        expectMatches("ncdfoe", "NoClassDefFoundException")
        expectMatches("fob", "FOO_BAR")
        expectMatches("fo_b", "FOO_BAR")
        expectMatches("fob", "FOO BAR")
        expectMatches("fo b", "FOO BAR")
        expectMatches("em", "emptyList")
        expectMatches("bui", "BuildConfig.groovy")
        expectMatches("buico", "BuildConfig.groovy")
        expectMatches("buico.gr", "BuildConfig.groovy")
        expectMatches("bui.gr", "BuildConfig.groovy")
        expectMatches("*fz", "azzzfzzz")
        expectMatches("WebLogic", "Weblogic")
        expectMatches("WebLOgic", "WebLogic")
        expectMatches("WEbLogic", "WebLogic")
        expectNoMatch("WebLogic", "Webologic")
        expectMatches("Wlo", "WebLogic")
    }

    @Test func ignoreCaseWhenCompleteMatch() {
        expectMatches("comboBox", "combobox")
        expectMatches("combobox", "comboBox")
        expectMatches("ABC_B.C", "abc_b.c")
    }

    @Test func capsMayMatchNonCaps() {
        expectMatches("PDFRe", "PdfRenderer")
        expectMatches("*pGETPartTimePositionInfo", "dbo.pGetPartTimePositionInfo.sql")
    }

    @Test func capitalAfterCapitalMayMatchLowercaseWhenShiftWasHeldTooLong() {
        expectMatches("USerDefa", "UserDefaults")
        expectMatches("NSUSerDefa", "NSUserDefaults")
        expectMatches("NSUSER", "NSUserDefaults")
        expectMatches("NSUSD", "NSUserDefaults")
        expectMatches("NSUserDEF", "NSUserDefaults")
    }

    @Test func lowerCaseAfterCamels() {
        expectMatches("LSTMa", "LineStatusTrackerManager")
    }

    @Test func cyrillicPatternMatchesLatinNameThroughLayoutFix() {
        expectMatches("ыек", "String")
    }

    @Test func swiftStyleNames() {
        expectMatches("CV", "ContentView.swift")
        expectMatches("conview", "ContentView")
        expectMatches("UsSe", "UserService")
        expectNoMatch("*pcl", "ApplicationController")
        expectNoMatch("*ogn", "login")
    }
}

@Suite("MinusculeMatcher wildcards and separators")
struct MinusculeMatcherWildcardTests {
    @Test func spaceDelimiters() {
        expectMatches("Na Ut Te", "name util test")
        expectMatches("Na Ut Te", "name Util Test")
        expectNoMatch("Na Ut Ta", "name Util Test")
        expectMatches("na ut te", "name util test")
        expectMatches("na ut", "name_util_test")
        expectMatches("na te", "name_util_test")
        expectNoMatch("na ti", "name_util_test")
        expectNoMatch("alias imple", "alias simple")
        expectNoMatch("alias mple", "alias simple")
        expectNoMatch("alias nother", "alias another")
    }

    @Test func spaceForAnyWordsInBetween() {
        expectMatches("fo bar", "fooBar")
        expectMatches("foo bar", "fooBar")
        expectMatches("foo bar", "fooGooBar")
        expectMatches("foo bar", "fooGoo bar")
        expectNoMatch(" b", "fbi")
        expectNoMatch(" for", "performAction")
        expectMatches(" us", "getUsage")
        expectMatches(" us", "getMyUsage")
    }

    @Test func filenamesWithDotsAndSpaces() {
        expectMatches("Google Test.html", "Google Test Test.cc.html")
        expectMatches("Google.html", "Google Test Test.cc.html")
        expectMatches("Google .html", "Google Test Test.cc.html")
        expectMatches("Google Test*.html", "Google Test Test.cc.html")
    }

    @Test func startDot() {
        expectMatches("A*.html", "A.html")
        expectMatches("A*.html", "Abc.html")
        expectMatches("A*.html", "after.html")
        expectNoMatch("A*.html", "10_after.html")
    }

    @Test func commonFileNameConventions() {
        expectMatches("BLWN", "base_layout_without_navigation.xhtml")
        expectMatches("BLWN", "base-layout-without-navigation.xhtml")
        expectMatches("FC", "faces-config.xml")
        expectMatches("ARS", "activity_report_summary.jsp")
        expectMatches("AD", "arrow_down.gif")
        expectMatches("VL", "vehicle-listings.css")
        expectMatches("ARS.j", "activity_report_summary.jsp")
        expectNoMatch("ARS.j", "activity_report_summary.xml")
        expectNoMatch("ARS.j", "activity_report_summary_justsometingwrong.xml")
        expectMatches("foo.goo", "foo.bar.goo")
        expectNoMatch("*.ico", "sm.th.iks.concierge")
    }

    @Test func extensionAfterHumps() {
        for name in ["add_relationship.jsp", "advanced_rule.jsp", "alarm_reduction.jsp", "audiot_report.jsp",
                     "audiot_r.jsp", "alarm_rule_action.jsp", "alarm_rule_admin.jsp",
                     "alarm_rule_administration.jsp", "alarm_rule_controller.jsp", "alarm_rule_frame.jsp",
                     "alarm_rule_severity.jsp", "AddRelationship.jsp", "AdvancedRule.jsp", "AlarmReduction.jsp",
                     "AudiotReport.jsp", "AudiotR.jsp", "AlarmRuleAction.jsp", "AlarmRuleAdmin.jsp",
                     "AlarmRuleAdministration.jsp", "AlarmRuleController.jsp", "AlarmRuleFrame.jsp",
                     "AlarmRuleSeverity.jsp"] {
            expectMatches("AR.jsp", name)
        }
    }

    @Test func skipDot() {
        expectMatches("ja", "jquery.autocomplete.js")
        expectNoMatch("ja.js", "jquery.autocomplete.js")
        expectMatches("jajs", "jquery.autocomplete.js")
        expectMatches("jjs", "jquery.autocomplete.js")
        expectMatches("j.js", "jquery.autocomplete.js")
        expectNoMatch("j.ajs", "jquery.autocomplete.js")
        expectMatches("oracle.bnf", "oracle-11.2.bnf")
        expectMatches("*foo.*bar", "foo.b.bar")
    }

    @Test func noExtension() {
        expectMatches("#.p", "#.php")
        expectMatches("#", "#.php")
        expectMatches("a", "a.php")
    }

    @Test func startsWithDot() {
        expectMatches(".foo", ".foo")
    }

    @Test func properDotEscaping() {
        expectMatches("*inspection*.pro", "InspectionsBundle.properties")
        expectNoMatch("*inspection*.pro", "InspectionsInProgress.png")
    }

    @Test func leadingUnderscore() {
        expectNoMatch("form", "_form.html.erb")
        expectMatches("_form", "_form.html.erb")
        expectMatches("_form", "__form")
        expectFirstLetterMatches("_form", "__form")
    }

    @Test func objectiveCSelectors() {
        expectMatches("h*:", "h:aaa")
        expectMatches("h:", "h:aaa")
        expectMatches("text:sh", "textField:shouldChangeCharactersInRange:replacementString:")
        expectMatches("abc", "aaa:bbb:ccc")
        expectMatches("textField:sh", "textField:shouldChangeCharactersInRange:replacementString:")
        expectMatches("text*:sh", "textField:shouldChangeCharactersInRange:replacementString:")
    }

    @Test func plusAndMinusMayBeSpaceSurrounded() {
        expectMatches("a+b", "alpha+beta")
        expectMatches("a+b", "alpha_gamma+beta")
        expectMatches("a+b", "alpha + beta")
        expectMatches("Foo+", "Foo+Bar.txt")
        expectMatches("Foo+", "Foo + Bar.txt")
        expectMatches("a", "alpha+beta")
        expectMatches("*b", "alpha+beta")
        expectMatches("a + b", "alpha+beta")
        expectMatches("a+", "alpha+beta")
        expectNoMatch("a ", "alpha+beta")
        expectMatches("", "alpha+beta")
        expectMatches("*+ b", "alpha+beta")
        expectNoMatch("d+g", "alphaDelta+betaGamma")
        expectMatches("*d+g", "alphaDelta+betaGamma")
        expectMatches("a-b", "alpha-beta")
        expectMatches("a-b", "alpha - beta")
    }

    @Test func finalSpaceForcesWholeWord() {
        expectMatches("a ", "alpha + beta")
        expectMatches("a ", "a ")
        expectMatches("a ", "a")
        expectMatches("GrDebT ", "GroovyDebuggerTest")
        expectNoMatch("grdebT ", "GroovyDebuggerTest")
        expectNoMatch("grdebt ", "GroovyDebuggerTest")
        expectMatches("Foo ", "Foo")
        expectNoMatch("Foo ", "FooBar")
        expectNoMatch("Foo ", "Foox")
        expectNoMatch("Collections ", "CollectionSplitter")
        expectMatches("CollectionS ", "CollectionSplitter")
        expectMatches("*run ", "in Runnable.run")
        expectNoMatch("*l ", "AppDelegate")
        expectNoMatch("*le ", "AppDelegate")
        expectNoMatch("*leg ", "AppDelegate")
        #expect(makeMatcher("create ").matches("create module"))
    }

    @Test func digits() {
        expectMatches("foba4", "FooBar4")
        expectMatches("foba", "Foo4Bar")
        expectMatches("*TEST-* ", "TEST-001")
        expectMatches("*TEST-0* ", "TEST-001")
        expectMatches("*v2 ", "VARCHAR2")
        expectMatches("smart8co", "SmartType18CompletionTest")
        expectMatches("smart8co", "smart18completion")
    }

    @Test func digitsBetweenPatternDigitsAreNotSkipped() {
        expectNoMatch("*012", "001122")
        expectMatches("012", "0a1_22")
    }

    @Test func specialSymbols() {
        expectMatches("a@b", "a@bc")
        expectNoMatch("*@in", "a int")
        expectMatches("a/text", "a/Text")
        expectMatches("a/text", "a/bbbText")
    }

    @Test func properties() {
        expectMatches("*pro", "spring.activemq.pool.configuration.reconnect-on-exception")
    }

    @Test func hardSeparatorsBlockLowercaseHumps() {
        let name = "foo bar"
        #expect(makeMatcher("fb").matches(name))
        #expect(!makeMatcher("fb", hardSeparators: " ").matches(name))
        #expect(makeMatcher("fB", hardSeparators: " ").matches(name))
        #expect(makeMatcher("f b", hardSeparators: " ").matches(name))
    }

    @Test func hardSeparatorBeforeFirstFragmentLowersDegree() {
        let name = "foo bar"
        let plain = makeMatcher("*b")
        let separated = makeMatcher("*b", hardSeparators: " ")
        #expect(plain.match(name) == [4..<5])
        #expect(plain.matchingDegree(name) - separated.matchingDegree(name) == 2)
    }

    @Test func patternLongerThanCamelHumpLimitMatchesBySubstring() {
        let hundredAs = String(repeating: "a", count: 100)
        #expect(makeMatcher("*" + hundredAs).match("xx" + hundredAs) == [2..<102])
        #expect(makeMatcher(hundredAs + "a").match(hundredAs + "a") == [0..<101])
        #expect(makeMatcher(hundredAs + "a").match("x" + hundredAs) == nil)
        #expect(makeMatcher(hundredAs + "a").match("short") == nil)
    }
}

@Suite("MinusculeMatcher middle matches")
struct MinusculeMatcherMiddleMatchTests {
    @Test func minimumTwoConsecutiveLettersInWordMiddle() {
        expectMatches("*fo", "reformat")
        expectMatches("*f", "reFormat")
        expectMatches("*f", "format")
        expectMatches("*f", "Format")
        expectMatches("*Stri", "string")
        expectMatches("*f", "reformat")
        expectMatches("*f", "reformatCode")
        expectNoMatch("*fc", "reformatCode")
        expectNoMatch("*foc", "reformatCode")
        expectMatches("*forc", "reformatCode")
        expectNoMatch("*sTC", "LazyClassTypeConstructor")
        expectNoMatch("*Icon", "LEADING_CONSTRUCTOR")
        expectMatches("*I", "LEADING_CONSTRUCTOR")
        expectMatches("*i", "LEADING_CONSTRUCTOR")
        expectMatches("*in", "LEADING_CONSTRUCTOR")
        expectMatches("*ing", "LEADING_CONSTRUCTOR")
        expectNoMatch("*inc", "LEADING_CONSTRUCTOR")
        expectNoMatch("*ico", "drawLinePickedOut")
        expectMatches("*l", "AppDelegate")
        expectMatches("*le", "AppDelegate")
        expectMatches("*leg", "AppDelegate")
    }

    @Test func middleMatchingUnderscore() {
        expectMatches("*_dark", "collapseAll_dark.png")
        expectMatches("*_dark.png", "collapseAll_dark.png")
        expectMatches("**_dark.png", "collapseAll_dark.png")
        expectFirstLetterMatches("*_DARK", "A_DARK.png")
    }

    @Test func middleMatching() {
        expectMatches("*zz*", "ListConfigzzKey")
        expectMatches("*zz", "ListConfigzzKey")
        #expect(makeMatcher("*old").matches("folder"))
        expectMatches("SWU*H*7", "SWUpgradeHdlrFSPR7Test")
        expectMatches("SWU*H*R", "SWUpgradeHdlrFSPR7Test")
        expectMatches("SWU*H*R", "SWUPGRADEHDLRFSPR7TEST")
        expectMatches("*git", "GitBlaBla")
        expectMatches("*Git", "GitBlaBla")
        expectNoMatch("*get*A", "getClass")
        expectMatches("*git", "BlaGitBla")
        expectMatches("*Git", "BlaGitBla")
        expectFirstLetterMatches("*Git", "BlagitBla")
        expectMatches("*git", "BlagitBla")
        expectMatches("*Git*", "AtpGenerationItem")
        expectMatches("Collec*Util*", "CollectionUtils")
        expectMatches("Collec*Util*", "CollectionUtilsTest")
        expectMatches("*us", "usage")
        expectMatches(" us", "usage")
        expectMatches(" fo. ba", "getFoo.getBar")
        expectMatches(" File. sepa", "File.separator")
        expectMatches(" File. sepa", "File._separator")
        expectMatches(" File. _sepa", "File._separator")
        expectMatches(" _fo", "_foo")
        expectMatches("*BComp", "BaseComponent")
    }

    @Test func uppercasePrefixWithMiddleMatching() {
        expectMatches("*OS", "ios")
        expectMatches("*OS", "IOS")
        expectMatches("*OS", "osx")
        expectMatches("*OS", "OSX")
        expectFirstLetterMatches("*I", "ID")
        expectFirstLetterNoMatch("*I", "id")
    }

    @Test func asteriskEndingInsideUppercaseWord() {
        expectMatches("*LRUMap", "SLRUMap")
    }

    @Test func middleMatchingIsFirstLetterSensitive() {
        expectFirstLetterMatches(" cl", "getClass")
        expectFirstLetterNoMatch(" EUC-", "x-EUC-TW")
        expectFirstLetterMatches(" a", "aaa")
        expectFirstLetterNoMatch(" a", "Aaa")
        expectFirstLetterNoMatch(" _bl", "_top")
        expectFirstLetterNoMatch("*Ch", "char")
        expectFirstLetterMatches("*Codes", "CFLocaleCopyISOCountryCodes")
        expectFirstLetterNoMatch("*codes", "CFLocaleCopyISOCountryCodes")
        expectFirstLetterMatches("*codes", "getCFLocaleCopyISOCountryCodes")
        expectFirstLetterMatches("*Bcomp", "BaseComponent")
    }

    @Test func longPatternMatchesItself() {
        expectMatches(
            "Product.findByDateAndNameGreaterThanEqualsAndQualityGreaterThanEqual",
            "Product.findByDateAndNameGreaterThanEqualsAndQualityGreaterThanEqualsIntellijIdeaRulezzz"
        )
    }

    @Test func longPatternWithSpacesMatchesItselfAsOneFragment() {
        let text = "the class with its attributes mapped to fields of records parsed by an "
            + "{@link AbstractParser} or written by an {@link AbstractWriter}."
        #expect(makeMatcher(text).match(text) == [0..<text.utf16.count])
    }
}

@Suite("MinusculeMatcher case modes")
struct MinusculeMatcherCaseModeTests {
    @Test func firstLetterMode() {
        expectFirstLetterMatches("WebLogic", "WebLogic")
        expectFirstLetterNoMatch("webLogic", "WebLogic")
        expectFirstLetterMatches("cL", "class")
        expectFirstLetterMatches("CL", "Class")
        expectFirstLetterMatches("Cl", "CoreLoader")
        expectFirstLetterNoMatch("abc", "_abc")
    }

    @Test func matchCaseMode() {
        expectCaseSensitiveMatches("WebLogic", "WebLogic")
        expectCaseSensitiveNoMatch("webLogic", "weblogic")
        expectCaseSensitiveNoMatch("FOO", "foo")
        expectCaseSensitiveNoMatch("foo", "fOO")
        expectCaseSensitiveNoMatch("Wl", "WebLogic")
        expectCaseSensitiveMatches("WL", "WebLogic")
        expectCaseSensitiveNoMatch("WL", "Weblogic")
        expectCaseSensitiveNoMatch("WL", "weblogic")
        expectCaseSensitiveNoMatch("webLogic", "WebLogic")
        expectCaseSensitiveNoMatch("Str", "SomeThingRidiculous")
        expectCaseSensitiveNoMatch("*list*", "List")
        expectCaseSensitiveNoMatch("*list*", "AbstractList")
        expectCaseSensitiveNoMatch("java.util.list", "java.util.List")
        expectCaseSensitiveNoMatch("java.util.list", "java.util.AbstractList")
    }

    @Test func ignoreCaseModeAcceptsAnyCase() {
        let matcher = makeMatcher("foo")
        for name in ["foo", "Foo", "FOO", "fOo", "FooBar"] {
            #expect(matcher.matches(name), "foo should match \(name)")
        }
    }
}

@Suite("MinusculeMatcher fragments")
struct MinusculeMatcherFragmentTests {
    @Test func matchingFragments() {
        var sample = "NoClassDefFoundException"
        #expect(makeMatcher("ncldfou*ion").match(sample) == [0..<1, 2..<4, 7..<8, 10..<13, 21..<24])

        sample = "doGet(HttpServletRequest, HttpServletResponse):void"
        #expect(makeMatcher("d*st").match(sample) == [0..<1, 22..<24])
        #expect(makeMatcher("doge*st").match(sample) == [0..<4, 22..<24])

        sample = "_test"
        #expect(makeMatcher("_").match(sample) == [0..<1])
        #expect(makeMatcher("_t").match(sample) == [0..<2])
    }

    @Test func matchingFragmentsAreSorted() {
        #expect(makeMatcher("SWU*H*R").match("SWUPGRADEHDLRFSPR7TEST") == [0..<3, 9..<10, 12..<13])
    }

    @Test func preferCapsMatching() {
        #expect(makeMatcher("getCU").match("getCurrentUser") == [0..<4, 10..<11])
    }

    @Test func camelHumpWinsOverConsecutiveCaseMismatch() throws {
        let fragments = try #require(makeMatcher("GEN").match("GetExtendedName"))
        #expect(fragments.count == 3)
        expectPreference("GEN", less: "GetName", more: "GetExtendedName")
        expectPreference("*GEN", less: "GetName", more: "GetExtendedName")
    }

    @Test func fragmentsAreUTF16Offsets() {
        #expect(makeMatcher("*Foo").match("\u{1F600}Foo") == [2..<5])
        #expect(makeMatcher("*Foo").match("\u{1F600}\u{1F600}Foo") == [4..<7])
    }

    @Test func nonBMPNamesDoNotBreakScoring() {
        let matcher = makeMatcher("*Foo")
        #expect(matcher.matchingDegree("\u{1F600}Foo") > Int.min)
    }

    @Test func noMatchProducesNilAndMinimumDegree() {
        let matcher = makeMatcher("zzq")
        #expect(matcher.match("ContentView") == nil)
        #expect(matcher.matchingDegree("ContentView") == Int.min)
    }

    @Test func emptyFragmentsScoreZero() {
        #expect(makeMatcher("").matchingDegree("anything") == 0)
    }

    @Test func invalidExternalFragmentsAreRejected() {
        let matcher = makeMatcher("foo")
        #expect(matcher.matchingDegree("foo", valueStartCaseMatch: false, fragments: [0..<10]) == Int.min)
        #expect(matcher.matchingDegree("foo", valueStartCaseMatch: false, fragments: [3..<3]) == Int.min)
        #expect(matcher.matchingDegree("foo", valueStartCaseMatch: false, fragments: nil) == Int.min)
    }

    @Test func startMatchDetection() {
        #expect(makeMatcher("ab").isStartMatch("abc"))
        #expect(!makeMatcher("*bc").isStartMatch("abc"))
        #expect(!makeMatcher("xyz").isStartMatch("abc"))
        #expect(makeMatcher("").isStartMatch("abc"))
    }
}

@Suite("MinusculeMatcher matching degree")
struct MinusculeMatcherDegreeTests {
    @Test func degreeOrdering() {
        expectPreference("jscote", less: "JsfCompletionTest", more: "JSCompletionTest", mode: .ignoreCase)
        expectPreference("OCO", less: "OneCoolObject", more: "OCObject")
        expectPreference("MUp", less: "MavenUmlProvider", more: "MarkUp")
        expectPreference("MUP", less: "MarkUp", more: "MavenUmlProvider")
        expectPreference("CertificateExce", less: "CertificateEncodingException", more: "CertificateException")
        expectPreference("boo", less: "Boolean", more: "boolean", mode: .ignoreCase)
        expectPreference("Boo", less: "boolean", more: "Boolean", mode: .ignoreCase)
        expectPreference("getCU", less: "getCurrentSomething", more: "getCurrentUser")
        expectPreference("cL", less: "class", more: "coreLoader")
        expectPreference("cL", less: "class", more: "classLoader")
        expectPreference("inse", less: "InstrumentationError", more: "intSet", mode: .ignoreCase)
        expectPreference("String", less: "STRING", more: "String", mode: .ignoreCase)
        expectPreference("*String", less: "STRING", more: "String", mode: .ignoreCase)
    }

    @Test func camelHumpsAreBetterThanAllUppers() {
        expectPreference("ProVi", less: "PROVIDER", more: "ProjectView")
    }

    @Test func preferAdjacentWords() {
        expectPreference("*psfi", less: "PsiJavaFileBaseImpl", more: "PsiFileImpl", mode: .ignoreCase)
    }

    @Test func preferMatchesToTheEnd() {
        expectPreference("*e", less: "fileIndex", more: "file", mode: .ignoreCase)
    }

    @Test func preferences() {
        expectPreference(" fb", less: "FooBar", more: "_fooBar", mode: .ignoreCase)
        expectPreference("*foo", less: "barFoo", more: "foobar")
        expectPreference("*fo", less: "barfoo", more: "barFoo")
        expectPreference("*fo", less: "barfoo", more: "foo")
        expectPreference("*fo", less: "asdfo", more: "Foo", mode: .ignoreCase)
        expectPreference(" sto", less: "StackOverflowError", more: "ArrayStoreException", mode: .ignoreCase)
        expectPreference(" EUC-", less: "x-EUC-TW", more: "EUC-JP", mode: .firstLetter)
        expectPreference(" boo", less: "Boolean", more: "boolean", mode: .ignoreCase)
        expectPreference(" Boo", less: "boolean", more: "Boolean", mode: .ignoreCase)
        expectPreference("ob", less: "oci_bind_array_by_name", more: "obj")
        expectNoPreference("en", "ENABLED", "Enum", mode: .ignoreCase)
    }

    @Test func honorFirstLetterCaseInCompletion() {
        let matcher = makeMatcher("*pim")
        let lessName = "PImageDecoder"
        let moreName = "posIdMap"
        let less = matcher.matchingDegree(lessName, valueStartCaseMatch: true, fragments: matcher.match(lessName))
        let more = matcher.matchingDegree(moreName, valueStartCaseMatch: true, fragments: matcher.match(moreName))
        #expect(less < more)
    }

    @Test func preferWordBoundaryMatch() {
        expectPreference("*ap", less: "add_profile", more: "application", mode: .ignoreCase)
        expectPreference("*les", less: "configureByFiles", more: "getLookupElementStrings")
        expectPreference("*les", less: "configureByFiles", more: "getLookupElementStrings", mode: .ignoreCase)
        expectPreference("*ea", less: "LEADING", more: "NORTH_EAST", mode: .ignoreCase)
        expectPreference("*Icon", less: "isControlKeyDown", more: "getErrorIcon", mode: .ignoreCase)
        expectPreference("*icon", less: "isControlKeyDown", more: "getErrorIcon", mode: .ignoreCase)
        expectPreference("*Icon", less: "getInitControl", more: "getErrorIcon", mode: .ignoreCase)
        expectPreference("*icon", less: "getInitControl", more: "getErrorIcon", mode: .ignoreCase)
    }

    @Test func preferNoWordSkipping() {
        expectPreference("CBP", less: "CustomProcessBP", more: "ComputationBatchProcess", mode: .ignoreCase)
    }

    @Test func wordLengthDoesNotMatter() {
        expectNoPreference("PropComp", "PropertyComponent", "PropertiesComponent", mode: .ignoreCase)
    }

    @Test func matchStartDoesNotMatterForDegree() {
        expectNoPreference(" path", "getAbsolutePath", "findPath", mode: .firstLetter)
    }

    @Test func preferStartMatching() {
        expectPreference("*tree", less: "FooTree", more: "Tree", mode: .ignoreCase)
    }

    @Test func preferContiguousMatching() {
        expectPreference("*mappablejs", less: "mappable-js.scope.js", more: "MappableJs.js", mode: .ignoreCase)
    }

    @Test func meaningfulMatchingDegree() {
        #expect(makeMatcher(" EUC-").matchingDegree("x-EUC-TW") > Int.min)
    }

    @Test func filePatterns() {
        expectMatches("groovy*.jar", "groovy-1.7.jar")
        expectNoMatch("*.ico", "a.i.c.o")
    }
}

@Suite("MinusculeMatcher prefer-start wrapper")
struct MinusculeMatcherPreferStartTests {
    @Test func startMatchGetsTenThousandBonus() {
        let plain = MinusculeMatcher(pattern: "*tree")
        let preferring = MinusculeMatcher(pattern: "*tree", preferStartMatch: true)
        #expect(preferring.matchingDegree("Tree") - plain.matchingDegree("Tree") == 10000)
    }

    @Test func nonStartMatchHasNoBonus() {
        let plain = MinusculeMatcher(pattern: "*tree")
        let preferring = MinusculeMatcher(pattern: "*tree", preferStartMatch: true)
        #expect(preferring.matchingDegree("FooTree") == plain.matchingDegree("FooTree"))
    }

    @Test func startMatchBeatsBetterScoredNonStartMatch() {
        let matcher = MinusculeMatcher(pattern: "*ab", preferStartMatch: true)
        #expect(matcher.matchingDegree("Abstract_zzzzzzzzzzzzzzzzzzzz") > matcher.matchingDegree("x_ab"))
        #expect(matcher.matchingDegree("Abstract") - matcher.matchingDegree("x_ab") > 5000)
    }

    @Test func wrapperDoesNotChangeMatchingOrFragments() {
        let plain = MinusculeMatcher(pattern: "UsSe")
        let preferring = MinusculeMatcher(pattern: "UsSe", preferStartMatch: true)
        for name in ["UserService", "MyUserService", "Unrelated"] {
            #expect(plain.match(name) == preferring.match(name))
            #expect(plain.matches(name) == preferring.matches(name))
        }
    }

    @Test func nilFragmentsStayAtMinimumDegree() {
        let matcher = MinusculeMatcher(pattern: "zz", preferStartMatch: true)
        #expect(matcher.matchingDegree("abc") == Int.min)
    }
}

@Suite("MinusculeMatcher keyboard layout fixing")
struct MinusculeMatcherLayoutTests {
    @Test func russianLayoutIsConvertedToLatin() {
        let matcher = MinusculeMatcher(pattern: "руддщ")
        #expect(matcher.matches("hello"))
        #expect(matcher.match("hello") == [0..<5])
        #expect(matcher.matches("HelloWorld"))
        #expect(!matcher.matches("world"))
    }

    @Test func layoutFixingCanBeDisabled() {
        let matcher = MinusculeMatcher(pattern: "руддщ", fixKeyboardLayout: false)
        #expect(!matcher.matches("hello"))
        #expect(matcher.matches("руддщ"))
    }

    @Test func uppercaseCyrillicKeepsItsCase() {
        let matcher = MinusculeMatcher(pattern: "Руддщ", mode: .matchCase)
        #expect(matcher.matches("Hello"))
        #expect(!matcher.matches("hello"))
    }

    @Test func patternWithLatinLetterIsNotConverted() {
        let matcher = MinusculeMatcher(pattern: "hелло")
        #expect(!matcher.matches("hello"))
    }

    @Test func fixedLayoutDegreeEqualsLatinPatternDegree() {
        let cyrillic = MinusculeMatcher(pattern: "*руддщ")
        let latin = MinusculeMatcher(pattern: "*hello")
        for name in ["hello", "HelloWorld", "say_hello"] {
            #expect(cyrillic.matchingDegree(name) == latin.matchingDegree(name))
            #expect(cyrillic.match(name) == latin.match(name))
        }
    }

    @Test func directMatchWinsOverFixedLayout() {
        let matcher = MinusculeMatcher(pattern: "пр")
        #expect(matcher.match("привет") == [0..<2])
        #expect(matcher.match("gh") == [0..<2])
    }

    @Test func fixLayoutTable() {
        #expect(RussianToEnglishKeyboardLayout.fixLayout("ыек") == "str")
        #expect(RussianToEnglishKeyboardLayout.fixLayout("ЫЕК") == "STR")
        #expect(RussianToEnglishKeyboardLayout.fixLayout("str") == nil)
        #expect(RussianToEnglishKeyboardLayout.fixLayout("123") == nil)
        #expect(RussianToEnglishKeyboardLayout.fixLayout("хъ") == "[]")
        #expect(RussianToEnglishKeyboardLayout.fixLayout("ж.") == ";/")
    }

    @Test func patternProperty() {
        #expect(MinusculeMatcher(pattern: "*foo* ").pattern == "*foo")
        #expect(MinusculeMatcher(pattern: "foo").pattern == "foo")
    }
}

@Suite("MinusculeMatcher non-ASCII and boundary branches")
struct MinusculeMatcherBoundaryTests {
    @Test func nonAsciiPatternCharactersAreMatchedIgnoringCase() {
        #expect(makeMatcher("bé").match("BaseÉtat") == [0..<1, 4..<5])
        #expect(makeMatcher("*é").match("caféé") == [3..<4])
        #expect(makeMatcher("αβ").match("ΑλφαΒήτα") == [0..<1, 4..<5])
        #expect(makeMatcher("*ñ").match("Español") == [4..<5])
    }

    @Test func nonAsciiPatternCharacterMissingFromNameDoesNotMatch() {
        expectNoMatch("bé", "BaseEtat")
        expectNoMatch("*ñ", "Espanol")
    }

    @Test func starPatternBeyondCamelHumpLimitWithoutOccurrenceDoesNotMatch() {
        let hundredAs = String(repeating: "a", count: 100)
        #expect(makeMatcher("*" + hundredAs).match(String(repeating: "b", count: 150)) == nil)
        #expect(makeMatcher("*" + hundredAs).match(String(repeating: "a", count: 99)) == nil)
    }

    @Test func hardSeparatorAbsentFromTheNameLeavesTheDegreeUntouched() {
        let separated = makeMatcher("fb", hardSeparators: " ")
        let plain = makeMatcher("fb")
        #expect(separated.match("fooBar") == [0..<1, 3..<4])
        #expect(separated.matchingDegree("fooBar") == plain.matchingDegree("fooBar"))
    }

    @Test func externalFragmentCharactersOutsideThePatternAddNoCaseScore() {
        let matcher = makeMatcher("foo")
        let wholeName = matcher.matchingDegree("fxo", valueStartCaseMatch: false, fragments: [0..<3])
        let firstLetterOnly = matcher.matchingDegree("fxo", valueStartCaseMatch: false, fragments: [0..<1])
        #expect(wholeName == firstLetterOnly + 1)
    }
}
