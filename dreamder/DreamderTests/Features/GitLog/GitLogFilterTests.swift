import Foundation
import Testing
@testable import Dreamder

private func makeCommit(
    hash: String = "abcdef1234567890",
    parents: [String] = [],
    author: String = "Alice Smith",
    email: String = "alice@example.com",
    date: TimeInterval = 1_000,
    commitDate: TimeInterval? = nil,
    subject: String = "subject",
    message: String? = nil
) -> GitLogCommit {
    GitLogCommit(
        hash: hash,
        parents: parents,
        authorName: author,
        authorEmail: email,
        date: Date(timeIntervalSince1970: date),
        commitDate: commitDate.map { Date(timeIntervalSince1970: $0) },
        refs: [],
        subject: subject,
        message: message
    )
}

@Suite
struct GitLogTextFilterTests {
    @Test
    func plainTextStaysPlainWhenRegexIsNotAllowed() {
        let filter = GitLogTextFilter.fromPattern("fix.*", isRegexpAllowed: false)
        #expect(!filter.isRegex)
        #expect(filter.text == "fix.*")
    }

    @Test
    func textWithoutRegexCharactersStaysPlainEvenWhenRegexIsAllowed() {
        #expect(!GitLogTextFilter.fromPattern("fix bug", isRegexpAllowed: true).isRegex)
    }

    @Test
    func textWithRegexCharactersBecomesRegexWhenAllowed() {
        #expect(GitLogTextFilter.fromPattern("fix.*", isRegexpAllowed: true).isRegex)
    }

    @Test
    func invalidRegexFallsBackToPlain() {
        let filter = GitLogTextFilter.fromPattern("(", isRegexpAllowed: true)
        #expect(!filter.isRegex)
        #expect(filter.text == "(")
    }

    @Test
    func matchCaseIsCarriedOver() {
        #expect(GitLogTextFilter.fromPattern("a", isMatchCase: true).matchesCase)
        #expect(!GitLogTextFilter.fromPattern("a").matchesCase)
    }

    @Test
    func plainMatcherIgnoresCaseByDefault() {
        let matcher = GitLogTextFilter.fromPattern("bug").matcher()
        #expect(matcher.matches("Fix Bug in parser"))
        #expect(!matcher.matches("Fix typo"))
    }

    @Test
    func plainMatcherHonoursMatchCase() {
        let matcher = GitLogTextFilter.fromPattern("Bug", isMatchCase: true).matcher()
        #expect(matcher.matches("Fix Bug"))
        #expect(!matcher.matches("fix bug"))
    }

    @Test
    func emptyPlainMatcherMatchesEverything() {
        #expect(GitLogTextFilter.fromPattern("").matcher().matches("anything"))
    }

    @Test
    func regexMatcherSearchesAnywhereAndIgnoresCaseByDefault() {
        let matcher = GitLogTextFilter.fromPattern("^fix", isRegexpAllowed: true).matcher()
        #expect(matcher.matches("Fixes the thing"))
        #expect(!matcher.matches("Does not fix"))
    }

    @Test
    func regexMatcherHonoursMatchCase() {
        let matcher = GitLogTextFilter.fromPattern("^fix", isRegexpAllowed: true, isMatchCase: true).matcher()
        #expect(matcher.matches("fixes"))
        #expect(!matcher.matches("Fixes"))
    }
}

@Suite
struct GitLogUserNamesTests {
    @Test
    func nameInStandardFormLowersFirstAndLastName() {
        #expect(GitLogUserNames.nameInStandardForm("John Smith") == "john smith")
    }

    @Test
    func nameInStandardFormTreatsPunctuationAsSeparator() {
        #expect(GitLogUserNames.nameInStandardForm("John.Smith") == "john smith")
        #expect(GitLogUserNames.nameInStandardForm("john_smith") == "john smith")
    }

    @Test
    func nameInStandardFormOfSingleWordIsLowerCased() {
        #expect(GitLogUserNames.nameInStandardForm("JOHN") == "john")
    }

    @Test
    func nameInStandardFormKeepsNonAsciiNames() {
        #expect(GitLogUserNames.nameInStandardForm("Ünal") == "Ünal")
    }

    @Test
    func firstAndLastNameSplitsOnSeparator() throws {
        let pair = try #require(GitLogUserNames.firstAndLastName("John Smith"))
        #expect(pair.0 == "John")
        #expect(pair.1 == "Smith")
    }

    @Test
    func firstAndLastNameAcceptsOneCharacterParts() throws {
        let pair = try #require(GitLogUserNames.firstAndLastName("a b"))
        #expect(pair.0 == "a")
        #expect(pair.1 == "b")
    }

    @Test(arguments: ["ab", "John", "John Ronald Smith", "Jörg Smith", "", "John "])
    func firstAndLastNameRejects(name: String) {
        #expect(GitLogUserNames.firstAndLastName(name) == nil)
    }

    @Test
    func nameToLowerCaseLowersAscii() {
        #expect(GitLogUserNames.nameToLowerCase("ABC def") == "abc def")
    }

    @Test
    func nameToLowerCaseKeepsNonAscii() {
        #expect(GitLogUserNames.nameToLowerCase("ÀBC") == "ÀBC")
    }

    @Test
    func nameFromEmailTakesTheLocalPart() {
        #expect(GitLogUserNames.nameFromEmail("john@example.com") == "john")
        #expect(GitLogUserNames.nameFromEmail("@example.com") == nil)
        #expect(GitLogUserNames.nameFromEmail("plain") == nil)
    }

    @Test
    func userNamePrefersNameThenEmailLocalPartThenEmail() {
        #expect(GitLogUserNames.userName(name: "John", email: "j@x.com") == "John")
        #expect(GitLogUserNames.userName(name: "", email: "j@x.com") == "j")
        #expect(GitLogUserNames.userName(name: "", email: "plain") == "plain")
    }

    @Test
    func extendedRegexAnchorsAndEscapesSpecialCharacters() {
        #expect(GitLogUserNames.extendedRegex(for: "a.b") == "^a\\.b$")
        #expect(GitLogUserNames.extendedRegex(for: "a-b+c") == "^a\\-b\\+c$")
        #expect(GitLogUserNames.extendedRegex(for: "(x)[y]{z}|^$*?") == "^\\(x\\)\\[y\\]\\{z\\}\\|\\^\\$\\*\\?$")
    }

    @Test
    func extendedRegexDoublesBackslashesWithoutEscapingThem() {
        #expect(GitLogUserNames.extendedRegex(for: "a\\b") == "^a\\\\b$")
    }

    @Test
    func extendedRegexLeavesNonSpecialCharactersUntouched() {
        #expect(GitLogUserNames.extendedRegex(for: "John Smith <js@x>") == "^John Smith <js@x>$")
    }

    @Test
    func escapeBackSlashesDoublesThem() {
        #expect(GitLogUserNames.escapeBackSlashes("a\\b") == "a\\\\b")
    }
}

@Suite
struct GitLogUserTests {
    @Test
    func emailIsLowerCased() {
        #expect(GitLogUser(name: "A", email: "A@X.COM").email == "a@x.com")
    }

    @Test
    func exactStringCombinesNameAndEmail() {
        #expect(GitLogUser(name: "Ada", email: "ada@x.com").exactString == "Ada <ada@x.com>")
        #expect(GitLogUser(name: "", email: "ada@x.com").exactString == "ada@x.com")
        #expect(GitLogUser(name: "Ada", email: "").exactString == "Ada")
    }

    @Test
    func shortPresentationUsesTheUserName() {
        #expect(GitLogUser(name: "", email: "ada@x.com").shortPresentation == "ada")
    }
}

@Suite
struct GitLogUserResolverTests {
    private let john = GitLogUser(name: "John Smith", email: "john@x.com")
    private let jane = GitLogUser(name: "Jane Doe", email: "jdoe@x.com")

    @Test
    func resolvesByStandardFormName() {
        let resolver = GitLogUserResolver(allUsers: [john, jane])
        #expect(resolver.resolveUserName("john smith") == [john])
        #expect(resolver.resolveUserName("John.Smith") == [john])
    }

    @Test
    func resolvesByEmailLocalPart() {
        let resolver = GitLogUserResolver(allUsers: [john, jane])
        #expect(resolver.resolveUserName("john") == [john])
        #expect(resolver.resolveUserName("JDOE") == [jane])
    }

    @Test
    func unknownNameResolvesToNothing() {
        let resolver = GitLogUserResolver(allUsers: [john, jane])
        #expect(resolver.resolveUserName("nobody").isEmpty)
    }

    @Test
    func duplicateUsersAreCollapsed() {
        let resolver = GitLogUserResolver(allUsers: [john, john, GitLogUser(name: "John Smith", email: "JOHN@X.COM")])
        #expect(resolver.allUsers == [john])
    }

    @Test
    func nameAndEmailMatchesAreUnioned() {
        let named = GitLogUser(name: "jane", email: "other@z.com")
        let mailed = GitLogUser(name: "Jane Doe", email: "jane@x.com")
        let resolver = GitLogUserResolver(allUsers: [named, mailed])
        #expect(resolver.resolveUserName("jane") == [named, mailed])
    }

    @Test
    func usersOfCommitsKeepsAuthorsInOrder() {
        let commits = [
            makeCommit(author: "A", email: "A@X.com"),
            makeCommit(author: "B", email: "b@x.com")
        ]
        #expect(GitLogUserResolver.users(of: commits) == [
            GitLogUser(name: "A", email: "a@x.com"),
            GitLogUser(name: "B", email: "b@x.com")
        ])
    }

    @Test
    func currentUserResolvesByName() {
        let resolver = GitLogUserResolver(currentUser: john, allUsers: [john, jane])
        #expect(resolver.resolveCurrentUser() == [john])
    }

    @Test
    func currentUserWithoutKnownAuthorsResolvesToNothing() {
        #expect(GitLogUserResolver(currentUser: john, allUsers: [jane]).resolveCurrentUser().isEmpty)
    }

    @Test
    func missingCurrentUserResolvesToNothing() {
        #expect(GitLogUserResolver(allUsers: [john]).resolveCurrentUser().isEmpty)
    }

    @Test
    func currentUserEmailMatchIsRestrictedToEmailsOfNameMatches() {
        let unrelated = GitLogUser(name: "jane", email: "other@z.com")
        let first = GitLogUser(name: "Jane Doe", email: "jane@x.com")
        let second = GitLogUser(name: "Jane Doe", email: "jane@y.com")
        let current = GitLogUser(name: "Jane Doe", email: "jane@x.com")
        let resolver = GitLogUserResolver(currentUser: current, allUsers: [unrelated, first, second])
        #expect(resolver.resolveCurrentUser() == [first, second])
    }

    @Test
    func currentUserWithoutEmailLocalPartResolvesByNameOnly() {
        let current = GitLogUser(name: "John Smith", email: "")
        let resolver = GitLogUserResolver(currentUser: current, allUsers: [john])
        #expect(resolver.resolveCurrentUser() == [john])
    }
}

@Suite
struct GitLogUserFilterTests {
    private let alice = GitLogUser(name: "Alice Smith", email: "alice@example.com")
    private let bob = GitLogUser(name: "Bob Jones", email: "bob@example.com")

    @Test
    func meIsDisplayedAsMe() {
        #expect(GitLogUserFilter(userNames: ["*", "bob"]).displayText == "me, bob")
    }

    @Test
    func usersResolvesNamesAndMe() {
        let resolver = GitLogUserResolver(currentUser: alice, allUsers: [alice, bob])
        #expect(GitLogUserFilter(userNames: ["*", "bob"]).users(resolver: resolver) == [alice, bob])
    }

    @Test
    func usersAreDeduplicated() {
        let resolver = GitLogUserResolver(currentUser: alice, allUsers: [alice, bob])
        #expect(GitLogUserFilter(userNames: ["*", "alice", "Alice Smith"]).users(resolver: resolver) == [alice])
    }

    @Test
    func usersOfUnknownNamesAreEmpty() {
        let resolver = GitLogUserResolver(allUsers: [alice])
        #expect(GitLogUserFilter(userNames: ["zed"]).users(resolver: resolver).isEmpty)
    }

    @Test
    func matchesRegisteredAuthor() {
        let resolver = GitLogUserResolver(allUsers: [alice, bob])
        let filter = GitLogUserFilter(userNames: ["Alice Smith"])
        #expect(filter.matches(makeCommit(author: "Alice Smith", email: "ALICE@example.com"), resolver: resolver))
        #expect(!filter.matches(makeCommit(author: "Bob Jones", email: "bob@example.com"), resolver: resolver))
    }

    @Test
    func meMatchesTheCurrentUserOnly() {
        let resolver = GitLogUserResolver(currentUser: alice, allUsers: [alice, bob])
        let filter = GitLogUserFilter(userNames: [GitLogUserFilter.me])
        #expect(filter.matches(makeCommit(author: "Alice Smith", email: "alice@example.com"), resolver: resolver))
        #expect(!filter.matches(makeCommit(author: "Bob Jones", email: "bob@example.com"), resolver: resolver))
    }

    @Test
    func meWithoutCurrentUserMatchesNothing() {
        let resolver = GitLogUserResolver(allUsers: [alice])
        let filter = GitLogUserFilter(userNames: [GitLogUserFilter.me])
        #expect(!filter.matches(makeCommit(author: "Alice Smith", email: "alice@example.com"), resolver: resolver))
    }

    @Test
    func unregisteredNameMatchesAuthorNameIgnoringCase() {
        let filter = GitLogUserFilter(userNames: ["alice"])
        #expect(filter.matches(makeCommit(author: "Alice", email: "x@y.com"), resolver: GitLogUserResolver()))
    }

    @Test
    func unregisteredNameMatchesEmailPrefix() {
        let filter = GitLogUserFilter(userNames: ["alice"])
        #expect(filter.matches(makeCommit(author: "Someone", email: "Alice@y.com"), resolver: GitLogUserResolver()))
    }

    @Test
    func unregisteredNameDoesNotMatchOthers() {
        let filter = GitLogUserFilter(userNames: ["alice"])
        #expect(!filter.matches(makeCommit(author: "Bob", email: "bob@y.com"), resolver: GitLogUserResolver()))
        #expect(!filter.matches(makeCommit(author: "Bob", email: "malice@y.com"), resolver: GitLogUserResolver()))
    }

    @Test
    func anyOfTheNamesMatches() {
        let filter = GitLogUserFilter(userNames: ["carol", "bob"])
        #expect(filter.matches(makeCommit(author: "Bob", email: "b@y.com"), resolver: GitLogUserResolver()))
    }
}

@Suite
struct GitLogDateFilterTests {
    private func filter(after: TimeInterval?, before: TimeInterval?) -> GitLogDateFilter {
        GitLogDateFilter(
            after: after.map { Date(timeIntervalSince1970: $0) },
            before: before.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test
    func afterIsStrict() {
        let filter = filter(after: 100, before: nil)
        #expect(filter.matches(makeCommit(commitDate: 101)))
        #expect(!filter.matches(makeCommit(commitDate: 100)))
        #expect(!filter.matches(makeCommit(commitDate: 99)))
    }

    @Test
    func beforeIsStrict() {
        let filter = filter(after: nil, before: 100)
        #expect(filter.matches(makeCommit(commitDate: 99)))
        #expect(!filter.matches(makeCommit(commitDate: 100)))
        #expect(!filter.matches(makeCommit(commitDate: 101)))
    }

    @Test
    func afterAndBeforeFormAnOpenInterval() {
        let filter = filter(after: 100, before: 200)
        #expect(filter.matches(makeCommit(commitDate: 150)))
        #expect(!filter.matches(makeCommit(commitDate: 100)))
        #expect(!filter.matches(makeCommit(commitDate: 200)))
    }

    @Test
    func usesTheCommitDateNotTheAuthorDate() {
        let filter = filter(after: 100, before: nil)
        #expect(!filter.matches(makeCommit(date: 500, commitDate: 50)))
        #expect(filter.matches(makeCommit(date: 50, commitDate: 500)))
    }

    @Test
    func unboundedFilterMatchesEverything() {
        #expect(filter(after: nil, before: nil).matches(makeCommit()))
    }
}

@Suite
struct GitLogParentFilterTests {
    private func commit(parents: Int) -> GitLogCommit {
        makeCommit(parents: (0..<parents).map { "p\($0)" })
    }

    @Test
    func noMergesMatchesRootsAndSingleParents() {
        #expect(GitLogParentFilter.noMerges.matches(commit(parents: 0)))
        #expect(GitLogParentFilter.noMerges.matches(commit(parents: 1)))
        #expect(!GitLogParentFilter.noMerges.matches(commit(parents: 2)))
    }

    @Test
    func onlyMergesMatchesTwoOrMoreParents() {
        #expect(!GitLogParentFilter.onlyMerges.matches(commit(parents: 1)))
        #expect(GitLogParentFilter.onlyMerges.matches(commit(parents: 2)))
        #expect(GitLogParentFilter.onlyMerges.matches(commit(parents: 3)))
    }

    @Test
    func defaultFilterMatchesAll() {
        let filter = GitLogParentFilter()
        #expect(filter.matchesAll)
        #expect(!filter.hasLowerBound)
        #expect(!filter.hasUpperBound)
        #expect(filter.matches(commit(parents: 5)))
    }

    @Test
    func boundsAreReported() {
        #expect(GitLogParentFilter.noMerges.hasUpperBound)
        #expect(!GitLogParentFilter.noMerges.hasLowerBound)
        #expect(GitLogParentFilter.onlyMerges.hasLowerBound)
        #expect(!GitLogParentFilter.onlyMerges.hasUpperBound)
        #expect(!GitLogParentFilter.noMerges.matchesAll)
    }

    @Test
    func isNoMergesRecognisesOnlyTheNoMergesShape() {
        #expect(GitLogParentFilter.noMerges.isNoMerges)
        #expect(!GitLogParentFilter.onlyMerges.isNoMerges)
        #expect(!GitLogParentFilter(minParents: 1, maxParents: 1).isNoMerges)
        #expect(!GitLogParentFilter().isNoMerges)
    }
}

@Suite
struct GitLogHashFilterTests {
    @Test
    func parsesWordsSeparatedByCommaSemicolonAndWhitespace() {
        let filter = GitLogHashFilter.fromText("abcdef1,1234567; 7654321\n fedcba9")
        #expect(filter?.hashes == ["abcdef1", "1234567", "7654321", "fedcba9"])
    }

    @Test
    func acceptsBoundaryLengths() {
        #expect(GitLogHashFilter.fromText(String(repeating: "a", count: 7)) != nil)
        #expect(GitLogHashFilter.fromText(String(repeating: "a", count: 64)) != nil)
    }

    @Test
    func acceptsUpperCaseHex() {
        #expect(GitLogHashFilter.fromText("ABCDEF1")?.hashes == ["ABCDEF1"])
    }

    @Test(arguments: [
        "",
        "   ",
        "abcdef",
        "abcdefg",
        "fix the bug",
        "abcdef1 notahash",
        "abcdef1, ,xyz"
    ])
    func rejectsTextThatIsNotOnlyHashes(text: String) {
        #expect(GitLogHashFilter.fromText(text) == nil)
    }

    @Test
    func rejectsTooLongWords() {
        #expect(GitLogHashFilter.fromText(String(repeating: "a", count: 65)) == nil)
    }

    @Test
    func matchesPrefixIgnoringCase() {
        let filter = GitLogHashFilter(hashes: ["ABCDEF1"])
        #expect(filter.matchesPrefix(makeCommit(hash: "abcdef1234567890")))
        #expect(!filter.matchesPrefix(makeCommit(hash: "0abcdef123456789")))
    }

    @Test
    func matchesAnyOfTheHashes() {
        let filter = GitLogHashFilter(hashes: ["1111111", "2222222"])
        #expect(filter.matchesPrefix(makeCommit(hash: "2222222aaaa")))
    }

    @Test
    func displayTextShortensToEightCharacters() {
        #expect(GitLogHashFilter(hashes: ["abcdef1234567890", "1234567"]).displayText == "abcdef12, 1234567")
    }

    @Test
    func multiPatternFilterMatchesAnyPatternIgnoringCase() {
        let textFilter = GitLogHashFilter(hashes: ["abcdef1", "1234567"]).toTextFilter()
        #expect(textFilter.matches("reverts ABCDEF1"))
        #expect(textFilter.matches("see 1234567"))
        #expect(!textFilter.matches("nothing"))
    }
}

@Suite
struct GitLogBranchFilterTests {
    @Test
    func emptyFilterMatchesEverything() {
        let filter = GitLogBranchFilter()
        #expect(filter.isEmpty)
        #expect(filter.matches("anything"))
    }

    @Test
    func includedBranchesMatchExactly() {
        let filter = GitLogBranchFilter.fromBranch("main")
        #expect(filter.matches("main"))
        #expect(!filter.matches("main2"))
        #expect(!filter.matches("dev"))
    }

    @Test
    func includedPatternsMatchTheWholeName() {
        let filter = GitLogBranchFilter(patterns: ["release/.*"])
        #expect(filter.matches("release/1.0"))
        #expect(!filter.matches("x/release/1.0"))
    }

    @Test
    func excludedBranchesAreRemovedFromAnOtherwiseOpenFilter() {
        let filter = GitLogBranchFilter(excludedBranches: ["dev"])
        #expect(filter.matches("main"))
        #expect(!filter.matches("dev"))
    }

    @Test
    func excludedPatternsWinOverIncludes() {
        let filter = GitLogBranchFilter(patterns: [".*"], excludedPatterns: ["tmp.*"])
        #expect(filter.matches("main"))
        #expect(!filter.matches("tmp-1"))
    }

    @Test
    func fromPatternsSplitsIncludesExcludesAndRegexes() {
        let filter = GitLogBranchFilter.fromPatterns(
            ["main", "feature/.*", "-dev", "-tmp.*"],
            existingBranches: ["main", "dev"]
        )
        #expect(filter.branches == ["main"])
        #expect(filter.patterns == ["feature/.*"])
        #expect(filter.excludedBranches == ["dev"])
        #expect(filter.excludedPatterns == ["tmp.*"])
    }

    @Test
    func existingBranchWithRegexCharactersIsNotARegex() {
        let filter = GitLogBranchFilter.fromPatterns(["release.1"], existingBranches: ["release.1"])
        #expect(filter.branches == ["release.1"])
        #expect(filter.patterns.isEmpty)
    }

    @Test
    func invalidRegexIsKeptAsABranchName() {
        let filter = GitLogBranchFilter.fromPatterns(["(["], existingBranches: ["main"])
        #expect(filter.branches == ["(["])
        #expect(filter.patterns.isEmpty)
    }

    @Test
    func notMatchedNamesAreExcludedWhenRequested() {
        let filter = GitLogBranchFilter.fromPatterns(
            ["main", "unknown", "-ghost"],
            existingBranches: ["main"],
            excludeNotMatched: true
        )
        #expect(filter.branches == ["main"])
        #expect(filter.excludedBranches.isEmpty)
    }

    @Test
    func notMatchedNamesAreKeptWithoutExistingBranches() {
        let filter = GitLogBranchFilter.fromPatterns(["unknown"], existingBranches: [], excludeNotMatched: true)
        #expect(filter.branches == ["unknown"])
    }

    @Test
    func notMatchedNamesAreKeptByDefault() {
        let filter = GitLogBranchFilter.fromPatterns(["unknown"], existingBranches: ["main"])
        #expect(filter.branches == ["unknown"])
    }

    @Test
    func displayTextListsIncludesThenExcludes() {
        let filter = GitLogBranchFilter(
            branches: ["main"],
            patterns: ["feature/.*"],
            excludedBranches: ["dev"],
            excludedPatterns: ["tmp.*"]
        )
        #expect(filter.displayText == "main, feature/.*, -dev, -tmp.*")
        #expect(!filter.isEmpty)
    }
}

@Suite
struct GitLogFilterCollectionTests {
    @Test
    func defaultCollectionIsEmpty() {
        let filters = GitLogFilterCollection()
        #expect(filters.isEmpty)
        #expect(filters.keys.isEmpty)
        #expect(!filters.hasDetailsFilters)
    }

    @Test
    func emptyBranchFilterAndEmptyStructureAndMatchAllParentAreNotKeys() {
        let filters = GitLogFilterCollection(
            branch: GitLogBranchFilter(),
            structure: GitLogStructureFilter(paths: []),
            parent: GitLogParentFilter()
        )
        #expect(filters.keys.isEmpty)
        #expect(filters.isEmpty)
    }

    @Test
    func keysReportEveryActiveFilter() {
        let filters = GitLogFilterCollection(
            branch: .fromBranch("main"),
            range: GitLogRangeFilter(ranges: []),
            revision: GitLogRevisionFilter(heads: ["abc"]),
            user: GitLogUserFilter(userNames: ["a"]),
            hash: GitLogHashFilter(hashes: ["abcdef1"]),
            date: GitLogDateFilter(after: Date(timeIntervalSince1970: 1), before: nil),
            text: GitLogTextFilter.fromPattern("x"),
            structure: GitLogStructureFilter(paths: ["a"]),
            parent: .noMerges
        )
        #expect(filters.keys == Set(GitLogFilterKey.allCases))
        #expect(!filters.isEmpty)
    }

    @Test
    func repositoryFiltersKeepOnlyBranchRangeRevisionAndStructure() {
        let filters = GitLogFilterCollection(
            branch: .fromBranch("main"),
            range: GitLogRangeFilter(ranges: [GitLogRefRange(exclusiveRef: "a", inclusiveRef: "b")]),
            revision: GitLogRevisionFilter(heads: ["abc"]),
            user: GitLogUserFilter(userNames: ["a"]),
            hash: GitLogHashFilter(hashes: ["abcdef1"]),
            date: GitLogDateFilter(after: Date(timeIntervalSince1970: 1), before: nil),
            text: GitLogTextFilter.fromPattern("x"),
            structure: GitLogStructureFilter(paths: ["a"]),
            parent: .noMerges
        )
        #expect(filters.repositoryFilters.keys == [.branch, .range, .revision, .structure])
    }

    @Test
    func detailsFiltersAreUserDateTextParentAndHash() {
        #expect(GitLogFilterCollection(user: GitLogUserFilter(userNames: ["a"])).hasDetailsFilters)
        #expect(GitLogFilterCollection(date: GitLogDateFilter(after: nil, before: Date())).hasDetailsFilters)
        #expect(GitLogFilterCollection(text: GitLogTextFilter.fromPattern("x")).hasDetailsFilters)
        #expect(GitLogFilterCollection(parent: .noMerges).hasDetailsFilters)
        #expect(GitLogFilterCollection(hash: GitLogHashFilter(hashes: ["abcdef1"])).hasDetailsFilters)
    }

    @Test
    func repositoryFiltersAreNotDetailsFilters() {
        let filters = GitLogFilterCollection(
            branch: .fromBranch("main"),
            revision: GitLogRevisionFilter(heads: ["abc"]),
            structure: GitLogStructureFilter(paths: ["a"])
        )
        #expect(!filters.hasDetailsFilters)
    }
}

@Suite
struct GitLogApplyingInMemoryTests {
    private let resolver = GitLogUserResolver()

    @Test
    func emptyCollectionKeepsEverything() {
        let commits = [makeCommit(hash: "1111111"), makeCommit(hash: "2222222")]
        #expect(GitLogFilterCollection().applyingInMemory(to: commits, resolver: resolver) == commits)
    }

    @Test
    func detailsFiltersAreCombinedWithAnd() {
        let fixAlice = makeCommit(hash: "1111111", author: "Alice", email: "a@x.com", message: "fix a")
        let otherAlice = makeCommit(hash: "2222222", author: "Alice", email: "a@x.com", message: "other")
        let fixBob = makeCommit(hash: "3333333", author: "Bob", email: "b@x.com", message: "fix b")
        let filters = GitLogFilterCollection(
            user: GitLogUserFilter(userNames: ["Alice"]),
            text: GitLogTextFilter.fromPattern("fix")
        )
        #expect(filters.applyingInMemory(to: [fixAlice, otherAlice, fixBob], resolver: resolver) == [fixAlice])
    }

    @Test
    func dateAndParentFiltersApply() {
        let old = makeCommit(hash: "1111111", parents: ["p"], commitDate: 10)
        let recentMerge = makeCommit(hash: "2222222", parents: ["p", "q"], commitDate: 500)
        let recent = makeCommit(hash: "3333333", parents: ["p"], commitDate: 500)
        let filters = GitLogFilterCollection(
            date: GitLogDateFilter(after: Date(timeIntervalSince1970: 100), before: nil),
            parent: .noMerges
        )
        #expect(filters.applyingInMemory(to: [old, recentMerge, recent], resolver: resolver) == [recent])
    }

    @Test
    func matchAllParentFilterIsIgnored() {
        let merge = makeCommit(parents: ["p", "q"])
        let filters = GitLogFilterCollection(parent: GitLogParentFilter())
        #expect(filters.applyingInMemory(to: [merge], resolver: resolver) == [merge])
    }

    @Test
    func hashFilterReturnsUnionOfPrefixAndMessageMatchesIgnoringOtherFilters() {
        let byPrefix = makeCommit(hash: "abcdef1234", message: "unrelated")
        let byMessage = makeCommit(hash: "9999999999", message: "reverts abcdef1")
        let neither = makeCommit(hash: "8888888888", message: "zzz")
        let filters = GitLogFilterCollection(
            hash: GitLogHashFilter(hashes: ["abcdef1"]),
            text: GitLogTextFilter.fromPattern("zzz")
        )
        #expect(filters.applyingInMemory(to: [byPrefix, byMessage, neither], resolver: resolver) == [byPrefix, byMessage])
    }

    @Test
    func hashFilterFallsThroughToOtherFiltersWhenNothingMatches() {
        let fix = makeCommit(hash: "1111111111", message: "fix it")
        let other = makeCommit(hash: "2222222222", message: "other")
        let filters = GitLogFilterCollection(
            hash: GitLogHashFilter(hashes: ["abcdef1"]),
            text: GitLogTextFilter.fromPattern("fix")
        )
        #expect(filters.applyingInMemory(to: [fix, other], resolver: resolver) == [fix])
    }

    @Test
    func emptyHashFilterFallsThrough() {
        let fix = makeCommit(hash: "1111111111", message: "fix it")
        let other = makeCommit(hash: "2222222222", message: "other")
        let filters = GitLogFilterCollection(
            hash: GitLogHashFilter(hashes: []),
            text: GitLogTextFilter.fromPattern("fix")
        )
        #expect(filters.applyingInMemory(to: [fix, other], resolver: resolver) == [fix])
    }

    @Test
    func textFilterMatchesTheFullMessage() {
        let body = makeCommit(hash: "1111111", subject: "title", message: "title\n\nmentions needle")
        let none = makeCommit(hash: "2222222", subject: "title", message: "title")
        let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("needle"))
        #expect(filters.applyingInMemory(to: [body, none], resolver: resolver) == [body])
    }

    @Test
    func userFilterUsesTheGivenResolver() {
        let alice = GitLogUser(name: "Alice Smith", email: "alice@example.com")
        let resolver = GitLogUserResolver(currentUser: alice, allUsers: [alice])
        let mine = makeCommit(hash: "1111111", author: "Alice Smith", email: "alice@example.com")
        let theirs = makeCommit(hash: "2222222", author: "Bob", email: "bob@example.com")
        let filters = GitLogFilterCollection(user: GitLogUserFilter(userNames: [GitLogUserFilter.me]))
        #expect(filters.applyingInMemory(to: [mine, theirs], resolver: resolver) == [mine])
    }
}

@Suite
struct GitLogFilterSettersTests {
    @Test
    func settingTextTrimsAndBuildsTextFilter() {
        let filters = GitLogFilterCollection().settingText("  hello world  ", isRegexpAllowed: false, isMatchCase: true)
        #expect(filters.text == GitLogTextFilter(text: "hello world", isRegex: false, matchesCase: true))
        #expect(filters.hash == nil)
    }

    @Test
    func settingTextDetectsRegexWhenAllowed() {
        let filters = GitLogFilterCollection().settingText("fix.*", isRegexpAllowed: true, isMatchCase: false)
        #expect(filters.text?.isRegex == true)
    }

    @Test
    func settingTextOfHashesAlsoSetsTheHashFilter() {
        let filters = GitLogFilterCollection().settingText("abcdef1, 1234567", isRegexpAllowed: false, isMatchCase: false)
        #expect(filters.hash?.hashes == ["abcdef1", "1234567"])
        #expect(filters.text?.text == "abcdef1, 1234567")
    }

    @Test
    func settingBlankTextClearsTextAndHash() {
        let start = GitLogFilterCollection().settingText("abcdef1", isRegexpAllowed: false, isMatchCase: false)
        let cleared = start.settingText("   ", isRegexpAllowed: false, isMatchCase: false)
        #expect(cleared.text == nil)
        #expect(cleared.hash == nil)
    }

    @Test
    func settingTextKeepsOtherFilters() {
        let start = GitLogFilterCollection(branch: .fromBranch("main"))
        #expect(start.settingText("x", isRegexpAllowed: false, isMatchCase: false).branch == .fromBranch("main"))
    }

    @Test
    func settingUserNamesBuildsOrClearsTheFilter() {
        let set = GitLogFilterCollection().settingUserNames(["a", "b"])
        #expect(set.user?.userNames == ["a", "b"])
        #expect(set.settingUserNames([]).user == nil)
    }

    @Test
    func settingDateBuildsOrClearsTheFilter() {
        let after = Date(timeIntervalSince1970: 100)
        let set = GitLogFilterCollection().settingDate(after: after, before: nil)
        #expect(set.date == GitLogDateFilter(after: after, before: nil))
        #expect(set.settingDate(after: nil, before: nil).date == nil)
    }

    @Test
    func settingPathsSplitsOnCommasAndNewlinesAndTrims() {
        let filters = GitLogFilterCollection().settingPaths(from: "a.txt, dir/b.txt\n c.txt\n,  ")
        #expect(filters.structure?.paths == ["a.txt", "dir/b.txt", "c.txt"])
    }

    @Test
    func settingBlankPathsClearsTheFilter() {
        let start = GitLogFilterCollection().settingPaths(from: "a")
        #expect(start.settingPaths(from: " , \n").structure == nil)
    }

    @Test
    func settingParentStoresAndClears() {
        let set = GitLogFilterCollection().settingParent(.noMerges)
        #expect(set.parent == .noMerges)
        #expect(set.settingParent(nil).parent == nil)
    }
}

@Suite
struct GitLogDatePresetTests {
    @Test
    func intervalsAreInSeconds() {
        #expect(GitLogDatePreset.last24Hours.interval == 86_400)
        #expect(GitLogDatePreset.last7Days.interval == 7 * 86_400)
        #expect(GitLogDatePreset.last30Days.interval == 30 * 86_400)
        #expect(GitLogDatePreset.lastYear.interval == 365 * 86_400)
    }

    @Test(arguments: GitLogDatePreset.allCases)
    func filterStartsOneIntervalBeforeNow(preset: GitLogDatePreset) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let filter = preset.filter(now: now)
        #expect(filter.after == now.addingTimeInterval(-preset.interval))
        #expect(filter.before == nil)
    }

    @Test
    func titlesAndIdentifiersAreStable() {
        #expect(GitLogDatePreset.allCases.map(\.title) == ["Last 24 hours", "Last 7 days", "Last 30 days", "Last year"])
        #expect(GitLogDatePreset.allCases.map(\.id) == ["last24Hours", "last7Days", "last30Days", "lastYear"])
    }
}
