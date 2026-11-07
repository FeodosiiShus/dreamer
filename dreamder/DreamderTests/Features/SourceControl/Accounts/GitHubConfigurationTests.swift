import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitHubTokenConfigurationTests {
    @Test
    func tokenIsBase64EncodedIntoTheBasicAuthorizationHeader() throws {
        let configuration = GitHubTokenConfiguration("secret")

        #expect(configuration.accessToken == "c2VjcmV0")
        #expect(configuration.authorizationHeader == "Basic")

        let request = try #require(GitHubIssueRouter.readIssue(configuration, "octo", "hello", 1).request())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic c2VjcmV0")
        #expect(request.url?.query == nil)
    }

    @Test
    func nonAsciiTokensAreEncodedFromTheirUTF8Bytes() {
        #expect(GitHubTokenConfiguration("tökén").accessToken == "dMO2a8Opbg==")
    }

    @Test
    func missingTokenSendsNoAuthorizationAtAll() throws {
        let configuration = GitHubTokenConfiguration()

        #expect(configuration.accessToken == nil)

        let request = try #require(GitHubIssueRouter.readIssue(configuration, "octo", "hello", 1).request())
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.query == nil)
    }

    @Test
    func defaultEndpointIsTheGitHubAPIAndCustomURLWins() {
        #expect(GitHubTokenConfiguration("t").apiEndpoint == "https://api.github.com/")
        #expect(GitHubTokenConfiguration("t", url: "https://ghe.example.com/api/v3/").apiEndpoint == "https://ghe.example.com/api/v3/")
    }

    @Test
    func errorDomainIsGitHubSpecific() {
        #expect(GitHubTokenConfiguration("t").errorDomain == "com.dreamder.models.accounts.github")
    }

    @Test
    func providerIsGitHub() {
        #expect(GitHubTokenConfiguration("t").provider == .github)
    }

    @Test
    func noPreviewHeadersMeansNoCustomHeaders() {
        #expect(GitHubTokenConfiguration("t").customHeaders?.isEmpty == true)
    }

    @Test
    func reactionsPreviewAddsAnAcceptHeaderToRequests() throws {
        let configuration = GitHubTokenConfiguration("secret", previewHeaders: [.reactions])

        #expect(configuration.customHeaders?.count == 1)
        #expect(configuration.customHeaders?.first?.headerField == "Accept")
        #expect(configuration.customHeaders?.first?.value == "application/vnd.github.squirrel-girl-preview")

        let request = try #require(GitHubIssueRouter.readIssue(configuration, "o", "r", 1).request())
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.squirrel-girl-preview")
    }
}

@Suite
struct GitHubOAuthConfigurationTests {
    private func configuration(
        url: String? = nil,
        webURL: String? = nil,
        scopes: [String] = ["repo", "user"]
    ) -> GitHubOAuthConfiguration {
        GitHubOAuthConfiguration(url, webURL: webURL, token: "cid", secret: "sec", scopes: scopes)
    }

    @Test
    func endpointsDefaultToTheGitHubProviderURLs() {
        let defaults = configuration()

        #expect(defaults.apiEndpoint == "https://api.github.com/")
        #expect(defaults.webEndpoint == "https://www.github.com/")
        #expect(defaults.errorDomain == "com.dreamder.models.accounts.github")
        #expect(defaults.token == "cid")
        #expect(defaults.secret == "sec")
        #expect(defaults.scopes == ["repo", "user"])
    }

    @Test
    func customEndpointsOverrideTheDefaults() {
        let custom = configuration(url: "https://ghe.example.com/api/v3/", webURL: "https://ghe.example.com/")

        #expect(custom.apiEndpoint == "https://ghe.example.com/api/v3/")
        #expect(custom.webEndpoint == "https://ghe.example.com/")
    }

    @Test
    func authenticateBuildsTheAuthorizeURLWithSortedEncodedQuery() {
        let url = configuration().authenticate()

        #expect(url?.absoluteString == "https://www.github.com/login/oauth/authorize?allow_signup=false&client_id=cid&scope=repo%2Cuser")
    }

    @Test
    func authenticateUsesTheEnterpriseWebEndpoint() {
        let url = configuration(webURL: "https://ghe.example.com/", scopes: ["gist"]).authenticate()

        #expect(url?.absoluteString == "https://ghe.example.com/login/oauth/authorize?allow_signup=false&client_id=cid&scope=gist")
    }

    @Test
    func authenticateWithEmptyScopesSendsAnEmptyScope() {
        let url = configuration(scopes: []).authenticate()

        #expect(url?.absoluteString == "https://www.github.com/login/oauth/authorize?allow_signup=false&client_id=cid&scope=")
    }

    @Test
    func authenticateReturnsNilWhenTheWebEndpointIsUnusable() {
        #expect(configuration(webURL: "").authenticate() == nil)
    }

    @Test
    func accessTokenIsExtractedFromTheFirstFormField() {
        let config = configuration()

        #expect(config.accessTokenFromResponse("access_token=gho_abc&scope=repo&token_type=bearer") == "gho_abc")
        #expect(config.accessTokenFromResponse("access_token=plain") == "plain")
        #expect(config.accessTokenFromResponse("") == "")
    }

    @Test
    func authorizeExchangesTheCodeAndReportsATokenConfiguration() throws {
        let session = FakeGitSession(status: 200, body: "access_token=gho_abc&scope=repo&token_type=bearer")
        let outcome = GitCallOutcome<GitHubTokenConfiguration>()

        configuration(url: "https://ghe.example.com/api/v3/").authorize(session, code: "code-1") {
            outcome.record($0, nil)
        }

        #expect(outcome.calls == 1)
        #expect(outcome.value?.accessToken == Data("gho_abc".utf8).base64EncodedString())
        #expect(outcome.value?.apiEndpoint == "https://ghe.example.com/api/v3/")

        let request = try #require(session.dataRequests.first)
        #expect(request.url?.absoluteString == "https://www.github.com/login/oauth/access_token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "client_id=cid&client_secret=sec&code=code-1")
    }

    @Test
    func authorizeIgnoresNonOKResponses() {
        let session = FakeGitSession(status: 401, body: "access_token=gho_abc")
        let outcome = GitCallOutcome<GitHubTokenConfiguration>()

        configuration().authorize(session, code: "c") { outcome.record($0, nil) }

        #expect(session.dataRequests.count == 1)
        #expect(outcome.calls == 0)
    }

    @Test
    func authorizeDoesNothingWhenTheWebEndpointIsUnusable() {
        let session = FakeGitSession(status: 200, body: "access_token=gho_abc")
        let outcome = GitCallOutcome<GitHubTokenConfiguration>()

        configuration(webURL: "").authorize(session, code: "c") { outcome.record($0, nil) }

        #expect(session.requestCount == 0)
        #expect(outcome.calls == 0)
    }

    @Test
    func handleOpenURLExchangesTheCodeFromTheCallbackQuery() throws {
        let session = FakeGitSession(status: 200, body: "access_token=gho_xyz")
        let outcome = GitCallOutcome<GitHubTokenConfiguration>()
        let callback = try #require(URL(string: "dreamder://oauth?code=abc123&state=s"))

        configuration().handleOpenURL(session, url: callback) { outcome.record($0, nil) }

        let body = try #require(session.dataRequests.first?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "client_id=cid&client_secret=sec&code=abc123")
        #expect(outcome.value?.accessToken == Data("gho_xyz".utf8).base64EncodedString())
    }

    @Test
    func handleOpenURLWithoutCodeDoesNotContactTheServer() throws {
        let session = FakeGitSession(status: 200, body: "access_token=gho_xyz")
        let outcome = GitCallOutcome<GitHubTokenConfiguration>()
        let callback = try #require(URL(string: "dreamder://oauth?error=access_denied"))

        configuration().handleOpenURL(session, url: callback) { outcome.record($0, nil) }

        #expect(session.requestCount == 0)
        #expect(outcome.calls == 0)
    }
}

@Suite
struct GitHubOAuthRouterTests {
    private let configuration = GitHubOAuthConfiguration(
        nil,
        webURL: nil,
        token: "cid",
        secret: "sec",
        scopes: ["repo"]
    )

    @Test
    func authorizeIsAGetWithURLEncoding() {
        let router = GitHubOAuthRouter.authorize(configuration)

        #expect(router.method == .GET)
        #expect(router.encoding == .url)
        #expect(router.path == "login/oauth/authorize")
        #expect(router.params as? [String: String] == ["scope": "repo", "client_id": "cid", "allow_signup": "false"])
    }

    @Test
    func accessTokenIsAFormPostWithClientCredentialsAndCode() throws {
        let router = GitHubOAuthRouter.accessToken(configuration, "the-code")

        #expect(router.method == .POST)
        #expect(router.encoding == .form)
        #expect(router.path == "login/oauth/access_token")
        #expect(router.params as? [String: String] == ["client_id": "cid", "client_secret": "sec", "code": "the-code"])

        let request = try #require(router.URLRequest)
        #expect(request.url?.absoluteString == "https://www.github.com/login/oauth/access_token")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "client_id=cid&client_secret=sec&code=the-code")
    }

    @Test
    func accessTokenBodyEscapesReservedCharactersInTheCode() throws {
        let request = try #require(GitHubOAuthRouter.accessToken(configuration, "a&b=c d").URLRequest)

        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "client_id=cid&client_secret=sec&code=a%26b%3Dc%20d")
    }

    @Test
    func routersTargetTheWebEndpointNotTheAPIEndpoint() throws {
        let enterprise = GitHubOAuthConfiguration(
            "https://ghe.example.com/api/v3/",
            webURL: "https://ghe.example.com/",
            token: "cid",
            secret: "sec",
            scopes: []
        )

        #expect(GitHubOAuthRouter.authorize(enterprise).URLRequest?.url?.host == "ghe.example.com")
        #expect(GitHubOAuthRouter.accessToken(enterprise, "c").URLRequest?.url?.path == "/login/oauth/access_token")
    }

    @Test
    func unusableWebEndpointYieldsNoRequest() {
        let broken = GitHubOAuthConfiguration("", webURL: "", token: "cid", secret: "sec", scopes: [])

        #expect(GitHubOAuthRouter.authorize(broken).URLRequest == nil)
        #expect(GitHubOAuthRouter.accessToken(broken, "c").URLRequest == nil)
    }
}
