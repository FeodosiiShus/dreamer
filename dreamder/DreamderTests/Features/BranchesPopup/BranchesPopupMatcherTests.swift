import Testing
@testable import Dreamder

@Suite
struct BranchesPopupMatcherTests {
    private func matcher(_ query: String) throws -> BranchesPopupMatcher {
        try #require(BranchesPopupMatcher(query: query))
    }

    @Test
    func emptyAndSlashQueriesDoNotFilter() {
        #expect(BranchesPopupMatcher(query: "") == nil)
        #expect(BranchesPopupMatcher(query: "   ") == nil)
        #expect(BranchesPopupMatcher(query: "/") == nil)
        #expect(BranchesPopupMatcher(query: " / ") == nil)
        #expect(BranchesPopupMatcher(query: "a") != nil)
    }

    @Test
    func matchesWordPrefix() throws {
        #expect(try matcher("feat").matches("feature/login"))
        #expect(try matcher("master").matches("master"))
    }

    @Test
    func matchesCamelHumps() throws {
        #expect(try matcher("cb").matches("checkoutBranch"))
        #expect(try matcher("fc").matches("fluxCapacitor"))
        #expect(try matcher("nbf").matches("newBranchFrom"))
    }

    @Test
    func matchesPathSegments() throws {
        #expect(try matcher("master").matches("origin/master"))
        #expect(try matcher("login").matches("feature/login"))
        #expect(try matcher("fl").matches("feature/login"))
    }

    @Test
    func matchesHyphenAndUnderscoreSegments() throws {
        #expect(try matcher("nb").matches("new-branch"))
        #expect(try matcher("nb").matches("new_branch"))
    }

    @Test
    func rejectsUnrelatedNames() throws {
        #expect(try matcher("xyz").matches("master") == false)
        #expect(try matcher("xyz").weight("master") == nil)
        #expect(try matcher("xyz").ranges("master") == nil)
    }

    @Test
    func matchesCaseInsensitively() throws {
        #expect(try matcher("feature").matches("FeatureLogin"))
        #expect(try matcher("openquick").matches("OpenQuicklyView"))
    }

    @Test
    func surroundingWhitespaceIsIgnored() throws {
        #expect(try matcher("  feat  ").matches("feature"))
        #expect(try matcher("  feat  ").ranges("feature") == (try matcher("feat").ranges("feature")))
    }

    @Test
    func weightAddsTenThousandMinusFirstFragmentStart() throws {
        let reference = MinusculeMatcher(pattern: "*log")
        let wrapped = try matcher("log")
        for name in ["login", "feature/login", "release/v2/login"] {
            let result = try #require(reference.matchWithDegree(name))
            let start = try #require(result.fragments.first?.lowerBound)
            #expect(wrapped.weight(name) == result.degree + 10000 - start)
        }
    }

    @Test
    func weightPrefersMatchesThatStartEarlier() throws {
        let wrapped = try matcher("login")
        let flat = try #require(wrapped.weight("login"))
        let nested = try #require(wrapped.weight("feature/login"))
        let deeper = try #require(wrapped.weight("release/feature/login"))
        #expect(flat > nested)
        #expect(nested > deeper)
    }

    @Test
    func reportsHighlightRangesAsCharacterOffsets() throws {
        #expect(try matcher("feat").ranges("feature/login") == [0..<4])
        #expect(try matcher("login").ranges("feature/login") == [8..<13])
        #expect(try matcher("feature").ranges("\u{1F600}feature") == [1..<8])
    }
}
