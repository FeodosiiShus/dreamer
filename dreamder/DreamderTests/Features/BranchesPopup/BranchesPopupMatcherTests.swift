import Testing
@testable import Dreamder

@Suite
struct BranchesPopupMatcherTests {
    @Test
    func matchesWordPrefix() {
        #expect(BranchesPopupMatcher.matches(query: "feat", candidate: "feature/login"))
        #expect(BranchesPopupMatcher.matches(query: "master", candidate: "master"))
    }

    @Test
    func matchesCamelHumps() {
        #expect(BranchesPopupMatcher.matches(query: "cb", candidate: "checkoutBranch"))
        #expect(BranchesPopupMatcher.matches(query: "fc", candidate: "fluxCapacitor"))
        #expect(BranchesPopupMatcher.matches(query: "nbf", candidate: "newBranchFrom"))
    }

    @Test
    func matchesAnywhereInTheName() {
        #expect(BranchesPopupMatcher.matches(query: "eature", candidate: "feature"))
        #expect(BranchesPopupMatcher.matches(query: "fc", candidate: "reformatCode"))
        #expect(!BranchesPopupMatcher.matches(query: "xyz", candidate: "master"))
    }

    @Test
    func matchesPathSegments() {
        #expect(BranchesPopupMatcher.matches(query: "fl", candidate: "feature/login"))
        #expect(BranchesPopupMatcher.matches(query: "master", candidate: "origin/master"))
        #expect(BranchesPopupMatcher.matches(query: "ol", candidate: "origin/login"))
        #expect(!BranchesPopupMatcher.matches(query: "fm", candidate: "feature/login"))
    }

    @Test
    func matchesHyphenAndUnderscoreSegments() {
        #expect(BranchesPopupMatcher.matches(query: "nb", candidate: "new-branch"))
        #expect(BranchesPopupMatcher.matches(query: "nb", candidate: "new_branch"))
        #expect(BranchesPopupMatcher.matches(query: "fm", candidate: "feature_merge"))
    }

    @Test
    func spaceSeparatesWords() {
        #expect(BranchesPopupMatcher.matches(query: "origin master", candidate: "origin/master"))
        #expect(BranchesPopupMatcher.matches(query: "or ma", candidate: "origin/master"))
        #expect(BranchesPopupMatcher.matches(query: "ma st", candidate: "master"))
    }

    @Test
    func matchesCaseInsensitively() {
        #expect(BranchesPopupMatcher.matches(query: "MASTER", candidate: "origin/master"))
        #expect(BranchesPopupMatcher.matches(query: "Feature", candidate: "featureLogin"))
    }

    @Test
    func emptyQueryMatchesEverything() {
        #expect(BranchesPopupMatcher.matches(query: "", candidate: "anything"))
        #expect(BranchesPopupMatcher.matches(query: "   ", candidate: "anything"))
    }

    @Test
    func scoresPrefixMatchesLower() throws {
        let prefixScore = try #require(BranchesPopupMatcher.score(query: "master", candidate: "master"))
        let nestedScore = try #require(BranchesPopupMatcher.score(query: "master", candidate: "origin/master"))
        #expect(prefixScore < nestedScore)
        #expect(BranchesPopupMatcher.score(query: "xyz", candidate: "master") == nil)
    }

    @Test
    func reportsHighlightRanges() {
        #expect(BranchesPopupMatcher.ranges(query: "feat", candidate: "feature/login") == [0..<4])
        #expect(BranchesPopupMatcher.ranges(query: "login", candidate: "feature/login") == [8..<13])
        #expect(BranchesPopupMatcher.ranges(query: "fl", candidate: "feature/login") == [0..<1, 8..<9])
        #expect(BranchesPopupMatcher.ranges(query: "zzz", candidate: "feature/login") == nil)
    }
}
