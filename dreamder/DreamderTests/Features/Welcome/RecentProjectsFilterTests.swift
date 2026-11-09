import Testing
@testable import Dreamder

struct RecentProjectsFilterTests {
    private let home = "/Users/me"

    private func project(_ path: String) -> RecentProject {
        RecentProject(
            path: path,
            displayName: RecentProject.displayName(forPath: path),
            projectOpenTimestamp: 0,
            isDirectory: true,
            hidden: false
        )
    }

    private var projects: [RecentProject] {
        [
            project("/Users/me/code/FooBar"),
            project("/Users/me/code/dreamder"),
            project("/Users/mellow/shared/notes"),
            project("/opt/tools/compiler")
        ]
    }

    private func names(_ query: String) -> [String] {
        RecentProjectsFilter.filter(projects, query: query, home: home).map(\.displayName)
    }

    @Test
    func anEmptyOrBlankQueryKeepsEverything() {
        #expect(names("").count == 4)
        #expect(names("  \n").count == 4)
    }

    @Test
    func theNameIsMatchedCaseInsensitively() {
        #expect(names("dream") == ["dreamder"])
        #expect(names("foobar") == ["FooBar"])
    }

    @Test
    func camelHumpsMatchTheName() {
        #expect(names("fb") == ["FooBar"])
    }

    @Test
    func thePathIsMatchedWithoutTheHomePrefix() {
        #expect(names("code") == ["FooBar", "dreamder"])
        #expect(names("users") == ["notes"])
        #expect(names("opt") == ["compiler"])
    }

    @Test
    func aSiblingOfTheHomeDirectoryKeepsItsFullPath() {
        #expect(names("mellow") == ["notes"])
        #expect(RecentProjectsFilter.searchName(for: project("/Users/mellow/shared/notes"), home: home)
            == " /Users/mellow/shared/notes notes")
    }

    @Test
    func theHomeItselfIsReducedToTheName() {
        #expect(RecentProjectsFilter.searchName(for: project("/Users/me"), home: home) == "  me")
        #expect(RecentProjectsFilter.searchName(for: project("/Users/me/code/FooBar"), home: home)
            == " /code/FooBar FooBar")
    }

    @Test
    func nothingMatchesAnUnrelatedQuery() {
        #expect(names("zzzqq").isEmpty)
    }
}
