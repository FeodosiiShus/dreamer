import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct GitCloneUrlValidationTests {
    private let model = GitCloneViewModel()

    @Test(arguments: [
        "http://a",
        "http://github.com/user/repo.git",
        "https://a",
        "https://github.com/user/repo.git",
        "git@a",
        "git@github.com:user/repo.git"
    ])
    func acceptsSupportedSchemesWithAtLeastOneCharacterAfterThePrefix(url: String) {
        #expect(model.isValidUrl(url: url))
    }

    @Test(arguments: ["http://", "https://", "git@"])
    func rejectsABarePrefixWithNothingAfterIt(url: String) {
        #expect(model.isValidUrl(url: url) == false)
    }

    @Test(arguments: [
        "HTTP://GITHUB.COM/USER/REPO",
        "HTTPS://GITHUB.COM/USER/REPO",
        "Https://github.com/user/repo",
        "GIT@GITHUB.COM:USER/REPO.GIT"
    ])
    func schemeMatchingIgnoresCase(url: String) {
        #expect(model.isValidUrl(url: url))
    }

    @Test(arguments: ["HTTP://", "HTTPS://", "GIT@"])
    func uppercaseBarePrefixIsStillRejected(url: String) {
        #expect(model.isValidUrl(url: url) == false)
    }

    @Test(arguments: [
        "",
        " ",
        "github.com/user/repo",
        "/Users/me/repo",
        "file:///Users/me/repo",
        "ftp://example.com/repo.git",
        "git://github.com/user/repo.git",
        "ssh://git@github.com/user/repo.git",
        "http:/example.com",
        "https:/example.com",
        "http//example.com",
        "git:user/repo",
        "gitx@github.com:user/repo.git",
        "user@github.com:user/repo.git"
    ])
    func rejectsUnsupportedOrMalformedUrls(url: String) {
        #expect(model.isValidUrl(url: url) == false)
    }

    @Test(arguments: [
        " https://github.com/user/repo",
        "\thttps://github.com/user/repo",
        "\nhttps://github.com/user/repo",
        " git@github.com:user/repo.git"
    ])
    func leadingWhitespaceIsNotTrimmed(url: String) {
        #expect(model.isValidUrl(url: url) == false)
    }

    @Test
    func trailingWhitespaceDoesNotInvalidateAnOtherwiseValidUrl() {
        #expect(model.isValidUrl(url: "https://github.com/user/repo.git "))
        #expect(model.isValidUrl(url: "https://github.com/user/repo.git\n"))
    }

    @Test
    func aSingleSpaceAfterABarePrefixCountsAsContent() {
        #expect(model.isValidUrl(url: "http:// "))
        #expect(model.isValidUrl(url: "https:// "))
        #expect(model.isValidUrl(url: "git@ "))
    }

    @Test
    func validationDoesNotDependOnTheStoredUrlString() {
        model.repoUrlStr = "https://github.com/user/repo"

        #expect(model.isValidUrl(url: "nonsense") == false)
        #expect(model.repoUrlStr == "https://github.com/user/repo")
    }
}
