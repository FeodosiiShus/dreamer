import Foundation
import Testing
@testable import Dreamder

@Suite
struct SourceControlAccountProviderTests {
    typealias Provider = SourceControlAccount.Provider

    @Test
    func idsAreStableLiteralsForEveryProvider() {
        #expect(Provider.bitbucketCloud.id == "bitbucketCloud")
        #expect(Provider.bitbucketServer.id == "bitbucketServer")
        #expect(Provider.github.id == "github")
        #expect(Provider.githubEnterprise.id == "githubEnterprise")
        #expect(Provider.gitlab.id == "gitlab")
        #expect(Provider.gitlabSelfHosted.id == "gitlabSelfHosted")
    }

    @Test
    func allCasesCoversSixProvidersWithUniqueIdsAndNames() {
        #expect(Provider.allCases.count == 6)
        #expect(Set(Provider.allCases.map(\.id)).count == 6)
        #expect(Set(Provider.allCases.map(\.name)).count == 6)
    }

    @Test
    func displayNamesMatchTheUI() {
        #expect(Provider.bitbucketCloud.name == "BitBucket Cloud")
        #expect(Provider.bitbucketServer.name == "BitBucket Server")
        #expect(Provider.github.name == "GitHub")
        #expect(Provider.githubEnterprise.name == "GitHub Enterprise")
        #expect(Provider.gitlab.name == "GitLab")
        #expect(Provider.gitlabSelfHosted.name == "GitLab Self-hosted")
    }

    @Test
    func hostedProvidersHaveBaseURLsAndSelfHostedOnesHaveNone() {
        #expect(Provider.bitbucketCloud.baseURL?.absoluteString == "https://www.bitbucket.com/")
        #expect(Provider.github.baseURL?.absoluteString == "https://www.github.com/")
        #expect(Provider.gitlab.baseURL?.absoluteString == "https://www.gitlab.com/")
        #expect(Provider.bitbucketServer.baseURL == nil)
        #expect(Provider.githubEnterprise.baseURL == nil)
        #expect(Provider.gitlabSelfHosted.baseURL == nil)
    }

    @Test
    func hostedProvidersHaveAPIURLsAndSelfHostedOnesHaveNone() {
        #expect(Provider.bitbucketCloud.apiURL?.absoluteString == "https://api.bitbucket.org/2.0/")
        #expect(Provider.github.apiURL?.absoluteString == "https://api.github.com/")
        #expect(Provider.gitlab.apiURL?.absoluteString == "https://gitlab.com/api/v4/")
        #expect(Provider.bitbucketServer.apiURL == nil)
        #expect(Provider.githubEnterprise.apiURL == nil)
        #expect(Provider.gitlabSelfHosted.apiURL == nil)
    }

    @Test
    func apiURLsEndWithASlashSoRelativePathsAppendInsteadOfReplace() throws {
        for provider in [Provider.bitbucketCloud, .github, .gitlab] {
            let api = try #require(provider.apiURL)
            #expect(api.absoluteString.hasSuffix("/"))
        }
        let gitlab = try #require(Provider.gitlab.apiURL)
        #expect(URL(string: "projects", relativeTo: gitlab)?.absoluteString == "https://gitlab.com/api/v4/projects")
        let bitbucket = try #require(Provider.bitbucketCloud.apiURL)
        #expect(URL(string: "user", relativeTo: bitbucket)?.absoluteString == "https://api.bitbucket.org/2.0/user")
    }

    @Test
    func authHelpURLsPointToTheTokenPagesOfEachProvider() {
        #expect(Provider.bitbucketCloud.authHelpURL?.absoluteString == "https://support.atlassian.com/bitbucket-cloud/docs/app-passwords/")
        #expect(Provider.bitbucketServer.authHelpURL?.absoluteString == "https://confluence.atlassian.com/bitbucketserver/personal-access-tokens-939515499.html")
        #expect(Provider.github.authHelpURL?.absoluteString == "https://github.com/settings/tokens/new")
        #expect(Provider.githubEnterprise.authHelpURL?.absoluteString == "https://github.com/settings/tokens/new")
        #expect(Provider.gitlab.authHelpURL?.absoluteString == "https://gitlab.com/-/profile/personal_access_tokens")
        #expect(Provider.gitlabSelfHosted.authHelpURL?.absoluteString == "https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html")
    }

    @Test
    func everyProviderHasAnAuthHelpURL() {
        #expect(Provider.allCases.allSatisfy { $0.authHelpURL?.scheme == "https" })
    }

    @Test
    func onlyBitbucketCloudAuthenticatesWithAPassword() {
        #expect(Provider.bitbucketCloud.authType == .password)
        #expect(Provider.allCases.filter { $0.authType == .password } == [.bitbucketCloud])
    }
}

@Suite
struct SourceControlAccountModelTests {
    private func account(
        provider: SourceControlAccount.Provider = .github,
        urlProtocol: SourceControlAccount.URLProtocol = .https
    ) -> SourceControlAccount {
        SourceControlAccount(
            id: "acc-1",
            name: "octocat",
            description: "work",
            provider: provider,
            serverURL: "https://ghe.example.com",
            urlProtocol: urlProtocol,
            sshKey: "ssh-key",
            isTokenValid: true
        )
    }

    @Test
    func urlProtocolRawValuesAreUppercase() {
        #expect(SourceControlAccount.URLProtocol.https.rawValue == "HTTPS")
        #expect(SourceControlAccount.URLProtocol.ssh.rawValue == "SSH")
        #expect(SourceControlAccount.URLProtocol.allCases == [.https, .ssh])
    }

    @Test(arguments: SourceControlAccount.Provider.allCases)
    func codableRoundTripPreservesEveryProvider(provider: SourceControlAccount.Provider) throws {
        let original = account(provider: provider, urlProtocol: .ssh)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SourceControlAccount.self, from: data)

        #expect(decoded == original)
        #expect(decoded.provider == provider)
        #expect(decoded.urlProtocol == .ssh)
    }

    @Test
    func encodedJSONStoresProtocolAsItsRawValue() throws {
        let data = try JSONEncoder().encode(account(urlProtocol: .https))

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["urlProtocol"] as? String == "HTTPS")
        #expect(json["id"] as? String == "acc-1")
        #expect(json["serverURL"] as? String == "https://ghe.example.com")
        #expect(json["isTokenValid"] as? Bool == true)
    }

    @Test
    func decodingRejectsAnUnknownURLProtocol() throws {
        let data = try JSONEncoder().encode(account())
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["urlProtocol"] = "FTP"
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SourceControlAccount.self, from: tampered)
        }
    }

    @Test
    func identityIsTheIdFieldAndEqualityCoversAllFields() {
        let first = account()
        var changed = account()
        changed.isTokenValid = false

        #expect(first.id == "acc-1")
        #expect(first != changed)
        #expect(Set([first, account()]).count == 1)
        #expect(Set([first, changed]).count == 2)
    }
}
