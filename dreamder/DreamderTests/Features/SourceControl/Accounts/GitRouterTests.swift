import Foundation
import Synchronization
import Testing
@testable import Dreamder

struct GitTestConfiguration: GitRouterConfiguration {
    var apiEndpoint: String?
    var accessToken: String?
    var accessTokenFieldName: String? = "access_token"
    var authorizationHeader: String?
    var errorDomain: String? = "com.dreamder.tests"
    var customHeaders: [GitHTTPHeader]?
}

struct GitMinimalConfiguration: GitRouterConfiguration {
    var apiEndpoint: String?
    var accessToken: String?
}

struct GitTestRouter: GitRouter {
    var method: GitHTTPMethod = .GET
    var path: String
    var encoding: GitHTTPEncoding = .url
    var params: [String: Any] = [:]
    var configuration: GitRouterConfiguration?
}

struct GitTestPayload: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

final class GitCallOutcome<T: Sendable>: Sendable {
    private struct State {
        var value: T?
        var error: Error?
        var calls = 0
    }

    private let state = Mutex(State())

    var value: T? { state.withLock { $0.value } }
    var error: Error? { state.withLock { $0.error } }
    var calls: Int { state.withLock { $0.calls } }

    @Sendable
    func record(_ value: T?, _ error: Error?) {
        state.withLock {
            $0.calls += 1
            $0.value = value
            $0.error = error
        }
    }
}

extension GitCallOutcome where T == Data {
    @Sendable
    func recordJSON(_ value: [String: Any]?, _ error: Error?) {
        record(value.flatMap { try? JSONSerialization.data(withJSONObject: $0) }, error)
    }

    var jsonObject: [String: Any]? {
        value.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

struct FakeGitTask: GitURLSessionDataTaskProtocol {
    let onResume: () -> Void

    func resume() {
        onResume()
    }
}

final class FakeGitSession: GitURLSession {
    var replyData: Data?
    var replyResponse: URLResponse?
    var replyError: Error?
    private(set) var dataRequests: [URLRequest] = []
    private(set) var uploadRequests: [URLRequest] = []
    private(set) var uploadBodies: [Data?] = []

    var requestCount: Int {
        dataRequests.count + uploadRequests.count
    }

    init(status: Int = 200, body: String = "", error: Error? = nil) {
        replyData = Data(body.utf8)
        replyResponse = HTTPURLResponse(
            url: URL(fileURLWithPath: "/"),
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )
        replyError = error
    }

    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> GitURLSessionDataTaskProtocol {
        dataRequests.append(request)
        let (data, response, error) = (replyData, replyResponse, replyError)
        return FakeGitTask { completionHandler(data, response, error) }
    }

    func uploadTask(
        with request: URLRequest,
        fromData bodyData: Data?,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> GitURLSessionDataTaskProtocol {
        uploadRequests.append(request)
        uploadBodies.append(bodyData)
        let (data, response, error) = (replyData, replyResponse, replyError)
        return FakeGitTask { completionHandler(data, response, error) }
    }

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        dataRequests.append(request)
        if let replyError { throw replyError }
        return (replyData ?? Data(), replyResponse ?? URLResponse())
    }

    func upload(
        for request: URLRequest,
        from bodyData: Data,
        delegate: URLSessionTaskDelegate?
    ) async throws -> (Data, URLResponse) {
        uploadRequests.append(request)
        uploadBodies.append(bodyData)
        if let replyError { throw replyError }
        return (replyData ?? Data(), replyResponse ?? URLResponse())
    }
}

@Suite
struct GitRouterRequestTests {
    private func router(
        endpoint: String?,
        path: String,
        params: [String: Any] = [:],
        method: GitHTTPMethod = .GET,
        encoding: GitHTTPEncoding = .url,
        token: String? = nil,
        fieldName: String? = "access_token",
        authorization: String? = nil,
        headers: [GitHTTPHeader]? = nil
    ) -> GitTestRouter {
        GitTestRouter(
            method: method,
            path: path,
            encoding: encoding,
            params: params,
            configuration: GitTestConfiguration(
                apiEndpoint: endpoint,
                accessToken: token,
                accessTokenFieldName: fieldName,
                authorizationHeader: authorization,
                customHeaders: headers
            )
        )
    }

    @Test
    func getRouterBuildsAbsoluteURLWithSortedQuery() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "repos/a/b/issues",
            params: ["state": "open", "per_page": "100", "page": "2"]
        ).request())

        #expect(request.url?.absoluteString == "https://api.example.com/repos/a/b/issues?page=2&per_page=100&state=open")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test
    func routerWithoutParamsHasNoQueryString() throws {
        let request = try #require(router(endpoint: "https://api.example.com/", path: "user").request())

        #expect(request.url?.absoluteString == "https://api.example.com/user")
    }

    @Test
    func endpointTrailingSlashDecidesWhetherPathPrefixSurvives() throws {
        let withSlash = try #require(router(endpoint: "https://example.com/api/v3/", path: "issues").request())
        let withoutSlash = try #require(router(endpoint: "https://example.com/api/v3", path: "issues").request())
        let bareHost = try #require(router(endpoint: "https://example.com", path: "issues").request())

        #expect(withSlash.url?.absoluteString == "https://example.com/api/v3/issues")
        #expect(withoutSlash.url?.absoluteString == "https://example.com/api/issues")
        #expect(bareHost.url?.absoluteString == "https://example.com/issues")
    }

    @Test
    func pathWithLeadingSlashResolvesFromHostRoot() throws {
        let request = try #require(router(endpoint: "https://example.com/api/v3/", path: "/user").request())

        #expect(request.url?.absoluteString == "https://example.com/user")
    }

    @Test
    func queryValuesArePercentEncodedButSlashIsKept() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "search",
            params: ["q": "a b&c=d/e", "r": "x+y:z#w"]
        ).request())

        #expect(request.url?.absoluteString == "https://api.example.com/search?q=a%20b%26c%3Dd/e&r=x%2By%3Az%23w")
    }

    @Test
    func tokenGoesIntoQueryWhenThereIsNoAuthorizationHeader() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "user",
            params: ["page": "1"],
            token: "a+b/c"
        ).request())

        #expect(request.url?.absoluteString == "https://api.example.com/user?access_token=a%2Bb/c&page=1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func tokenQueryNameFollowsAccessTokenFieldName() throws {
        let request = try #require(router(
            endpoint: "https://gitlab.example.com/api/v4/",
            path: "projects",
            token: "tok",
            fieldName: "private_token"
        ).request())

        #expect(request.url?.absoluteString == "https://gitlab.example.com/api/v4/projects?private_token=tok")
    }

    @Test
    func authorizationHeaderReplacesTheQueryToken() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "user",
            token: "tok",
            authorization: "Bearer"
        ).request())

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.url?.absoluteString == "https://api.example.com/user")
    }

    @Test
    func authorizationHeaderIsOmittedWithoutAToken() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "user",
            authorization: "Bearer"
        ).request())

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func customHeadersAreAddedToTheRequest() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "user",
            headers: [
                GitHTTPHeader(headerField: "X-One", value: "1"),
                GitHTTPHeader(headerField: "Accept", value: "application/vnd.example+json")
            ]
        ).request())

        #expect(request.value(forHTTPHeaderField: "X-One") == "1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.example+json")
    }

    @Test
    func jsonEncodingKeepsParametersOutOfTheURLAndBody() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "repos/a/b/issues",
            params: ["title": "Crash"],
            method: .POST,
            encoding: .json
        ).request())

        #expect(request.url?.absoluteString == "https://api.example.com/repos/a/b/issues")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == nil)
    }

    @Test
    func jsonEncodingStillSendsTheTokenInTheQuery() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "issues",
            params: ["title": "Crash"],
            method: .POST,
            encoding: .json,
            token: "tok"
        ).request())

        #expect(request.url?.absoluteString == "https://api.example.com/issues?access_token=tok")
    }

    @Test
    func formEncodingMovesSortedEncodedParametersIntoTheBody() throws {
        let request = try #require(router(
            endpoint: "https://api.example.com/",
            path: "login/token",
            params: ["b": "2", "a": "1 2"],
            method: .POST,
            encoding: .form
        ).request())

        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "a=1%202&b=2")
        #expect(request.url?.absoluteString == "https://api.example.com/login/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test(arguments: [GitHTTPMethod.GET, .POST, .PUT, .PATCH, .DELETE])
    func httpMethodIsCopiedToTheRequest(method: GitHTTPMethod) throws {
        let request = try #require(router(endpoint: "https://api.example.com/", path: "x", method: method).request())

        #expect(request.httpMethod == method.rawValue)
    }

    @Test
    func missingConfigurationEndpointOrEmptyEndpointYieldsNil() {
        let noConfiguration = GitTestRouter(path: "user", configuration: nil)

        #expect(noConfiguration.request() == nil)
        #expect(router(endpoint: nil, path: "user").request() == nil)
        #expect(router(endpoint: "", path: "user").request() == nil)
    }

    @Test
    func minimalConfigurationUsesTheProtocolDefaults() {
        let configuration = GitMinimalConfiguration(apiEndpoint: "https://x/", accessToken: "t")

        #expect(configuration.accessTokenFieldName == "access_token")
        #expect(configuration.authorizationHeader == nil)
        #expect(configuration.errorDomain == "com.dreamder.models.accounts.networking")
        #expect(configuration.customHeaders == nil)
    }

    @Test
    func minimalConfigurationSendsTheTokenAsAccessTokenQuery() throws {
        let request = try #require(GitTestRouter(
            path: "user",
            configuration: GitMinimalConfiguration(apiEndpoint: "https://x.example/", accessToken: "t")
        ).request())

        #expect(request.url?.absoluteString == "https://x.example/user?access_token=t")
    }
}

@Suite
struct GitRouterURLQueryTests {
    private let router = GitTestRouter(path: "x")

    private func rendered(_ parameters: [String: Any]) -> [String]? {
        router.urlQuery(parameters)?.map { "\($0.name)=\($0.value ?? "")" }
    }

    @Test
    func emptyParametersProduceNoQuery() {
        #expect(router.urlQuery([:]) == nil)
    }

    @Test
    func stringsAreSortedByKeyAndEscaped() {
        #expect(rendered(["b": "x y", "a": "1,2"]) == ["a=1%2C2", "b=x%20y"])
    }

    @Test
    func stringArraysUseIndexedBracketNames() {
        #expect(rendered(["labels": ["bug", "help wanted"]]) == ["labels[0]=bug", "labels[1]=help%20wanted"])
    }

    @Test
    func nestedDictionariesUseBracketedKeysAndSkipNonStrings() {
        let filter: [String: Any] = ["b": "2", "a": "1", "n": 5]

        #expect(rendered(["filter": filter]) == ["filter[a]=1", "filter[b]=2"])
    }

    @Test
    func unsupportedValueTypesAreSkipped() {
        #expect(rendered(["n": 5, "s": "x"]) == ["s=x"])
        #expect(router.urlQuery(["n": 5]) == [])
    }
}

@Suite
struct GitRouterLoadTests {
    private func router(endpoint: String? = "https://api.example.com/") -> GitTestRouter {
        GitTestRouter(
            path: "things/1",
            configuration: GitTestConfiguration(apiEndpoint: endpoint)
        )
    }

    @Test
    func loadDecodesASuccessfulResponse() throws {
        let session = FakeGitSession(status: 200, body: #"{"id":5,"name":"x"}"#)
        let outcome = GitCallOutcome<GitTestPayload>()

        let task = router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self, completion: outcome.record)

        #expect(task != nil)
        #expect(outcome.calls == 1)
        #expect(outcome.value == GitTestPayload(id: 5, name: "x"))
        #expect(outcome.error == nil)
        #expect(session.dataRequests.map { $0.url?.absoluteString } == ["https://api.example.com/things/1"])
    }

    @Test
    func loadReportsUndecodableBodiesAsDecodingErrors() {
        let session = FakeGitSession(status: 200, body: "[]")
        let outcome = GitCallOutcome<GitTestPayload>()

        _ = router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self, completion: outcome.record)

        #expect(outcome.value == nil)
        #expect(outcome.error is DecodingError)
    }

    @Test
    func loadMapsHTTPFailureToNSErrorWithServerJSON() throws {
        let session = FakeGitSession(status: 404, body: #"{"message":"Not Found"}"#)
        let outcome = GitCallOutcome<GitTestPayload>()

        _ = router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self, completion: outcome.record)

        let error = try #require(outcome.error.map { $0 as NSError })
        #expect(outcome.value == nil)
        #expect(error.domain == "com.dreamder.tests")
        #expect(error.code == 404)
        #expect((error.userInfo["ErrorKey"] as? [String: Any])?["message"] as? String == "Not Found")
    }

    @Test
    func loadForwardsTransportErrors() {
        let session = FakeGitSession(status: 200, body: "", error: URLError(.notConnectedToInternet))
        let outcome = GitCallOutcome<GitTestPayload>()

        _ = router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self, completion: outcome.record)

        #expect((outcome.error as? URLError)?.code == .notConnectedToInternet)
    }

    @Test
    func loadReturnsNilWithoutTouchingTheSessionWhenTheEndpointIsInvalid() {
        let session = FakeGitSession()
        let outcome = GitCallOutcome<GitTestPayload>()

        let task = router(endpoint: nil).load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self, completion: outcome.record)

        #expect(task == nil)
        #expect(session.requestCount == 0)
        #expect(outcome.calls == 0)
    }

    @Test
    func loadWithOnlyACompletionReportsStatusErrors() throws {
        let session = FakeGitSession(status: 500, body: #"{"message":"boom"}"#)
        let outcome = GitCallOutcome<Int>()

        _ = router().load(session, completion: { outcome.record(nil, $0) })

        let error = try #require(outcome.error.map { $0 as NSError })
        #expect(error.code == 500)
        #expect(error.domain == "com.dreamder.tests")
    }

    @Test
    func loadWithOnlyACompletionReportsNilErrorOnSuccess() {
        let session = FakeGitSession(status: 204)
        let outcome = GitCallOutcome<Int>()

        _ = router().load(session, completion: { outcome.record(nil, $0) })

        #expect(outcome.calls == 1)
        #expect(outcome.error == nil)
    }

    @Test
    func asyncLoadDecodesASuccessfulResponse() async throws {
        let session = FakeGitSession(status: 200, body: #"{"id":9,"name":"y"}"#)

        let payload = try await router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self)

        #expect(payload == GitTestPayload(id: 9, name: "y"))
    }

    @Test
    func asyncLoadThrowsMinus876ForAnInvalidEndpoint() async {
        let session = FakeGitSession()

        do {
            _ = try await router(endpoint: "").load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self)
            Issue.record("expected a throw")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == "com.dreamder.tests")
            #expect(nsError.code == -876)
        }
        #expect(session.requestCount == 0)
    }

    @Test
    func asyncLoadThrowsNSErrorForHTTPFailures() async {
        let session = FakeGitSession(status: 403, body: #"{"message":"Forbidden"}"#)

        do {
            _ = try await router().load(session, decoder: JSONDecoder(), expectedResultType: GitTestPayload.self)
            Issue.record("expected a throw")
        } catch {
            let nsError = error as NSError
            #expect(nsError.code == 403)
            #expect((nsError.userInfo["ErrorKey"] as? [String: Any])?["message"] as? String == "Forbidden")
        }
    }

    @Test
    func wasSuccessfulCoversExactly200Through299() {
        func response(_ status: Int) -> HTTPURLResponse? {
            HTTPURLResponse(url: URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
        }

        #expect(response(199)?.wasSuccessful == false)
        #expect(response(200)?.wasSuccessful == true)
        #expect(response(299)?.wasSuccessful == true)
        #expect(response(300)?.wasSuccessful == false)
    }
}

@Suite
struct GitHubIssueRouterTests {
    private let configuration = GitHubTokenConfiguration("secret")

    @Test
    func readIssueUsesRepositoryPathAndBasicAuthorization() throws {
        let request = try #require(GitHubIssueRouter.readIssue(configuration, "octo", "hello", 42).request())

        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/hello/issues/42")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic c2VjcmV0")
    }

    @Test
    func readIssuesSendsSortedPagingQuery() throws {
        let request = try #require(
            GitHubIssueRouter.readIssues(configuration, "octo", "hello", "1", "100", .open).request()
        )

        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/hello/issues?page=1&per_page=100&state=open")
    }

    @Test
    func readAuthenticatedIssuesHitsTheTopLevelIssuesPath() throws {
        let request = try #require(
            GitHubIssueRouter.readAuthenticatedIssues(configuration, "2", "50", .closed).request()
        )

        #expect(request.url?.absoluteString == "https://api.github.com/issues?page=2&per_page=50&state=closed")
    }

    @Test
    func enterpriseEndpointWithTrailingSlashKeepsItsPrefix() throws {
        let enterprise = GitHubTokenConfiguration("secret", url: "https://ghe.example.com/api/v3/")
        let request = try #require(GitHubIssueRouter.readIssue(enterprise, "octo", "hello", 1).request())

        #expect(request.url?.absoluteString == "https://ghe.example.com/api/v3/repos/octo/hello/issues/1")
    }

    @Test
    func commentPathsDifferBetweenIssueAndCommentEndpoints() {
        #expect(GitHubIssueRouter.commentIssue(configuration, "o", "r", 7, "hi").path == "repos/o/r/issues/7/comments")
        #expect(GitHubIssueRouter.readIssueComments(configuration, "o", "r", 7, "1", "30").path == "repos/o/r/issues/7/comments")
        #expect(GitHubIssueRouter.patchIssueComment(configuration, "o", "r", 9, "edit").path == "repos/o/r/issues/comments/9")
    }

    @Test
    func writeRoutersUsePostWithJSONEncodingAndReadRoutersUseGetWithURLEncoding() {
        let writes: [GitHubIssueRouter] = [
            .postIssue(configuration, "o", "r", "t", nil, nil, []),
            .patchIssue(configuration, "o", "r", 1, nil, nil, nil, nil),
            .commentIssue(configuration, "o", "r", 1, "b"),
            .patchIssueComment(configuration, "o", "r", 1, "b")
        ]
        let reads: [GitHubIssueRouter] = [
            .readIssue(configuration, "o", "r", 1),
            .readIssues(configuration, "o", "r", "1", "1", .all),
            .readAuthenticatedIssues(configuration, "1", "1", .all),
            .readIssueComments(configuration, "o", "r", 1, "1", "1")
        ]

        #expect(writes.allSatisfy { $0.method == .POST && $0.encoding == .json })
        #expect(reads.allSatisfy { $0.method == .GET && $0.encoding == .url })
    }

    @Test
    func postIssueParamsOmitMissingOptionalsAndEmptyLabels() {
        let minimal = GitHubIssueRouter.postIssue(configuration, "o", "r", "Only title", nil, nil, [])
        let full = GitHubIssueRouter.postIssue(configuration, "o", "r", "Crash", "Steps", "octocat", ["bug", "ui"])

        #expect(minimal.params as? [String: String] == ["title": "Only title"])
        #expect(full.params["title"] as? String == "Crash")
        #expect(full.params["body"] as? String == "Steps")
        #expect(full.params["assignee"] as? String == "octocat")
        #expect(full.params["labels"] as? [String] == ["bug", "ui"])
        #expect(full.params.count == 4)
    }

    @Test
    func patchIssueParamsContainOnlyProvidedFields() {
        let router = GitHubIssueRouter.patchIssue(configuration, "o", "r", 3, nil, "new body", nil, .closed)

        #expect(router.params as? [String: String] == ["body": "new body", "state": "closed"])
        #expect(GitHubIssueRouter.patchIssue(configuration, "o", "r", 3, nil, nil, nil, nil).params.isEmpty)
    }

    @Test
    func readIssueHasNoParams() {
        #expect(GitHubIssueRouter.readIssue(configuration, "o", "r", 3).params.isEmpty)
    }
}

@Suite
struct GitJSONPostRouterTests {
    private let configuration = GitHubTokenConfiguration("secret")

    @Test
    func postJSONUploadsParamsAsJSONToTheIssuesEndpoint() throws {
        let session = FakeGitSession(status: 201, body: #"{"id":7}"#)
        let outcome = GitCallOutcome<Data>()
        let router = GitHubIssueRouter.postIssue(configuration, "octo", "hello", "Crash", "Steps", "octocat", ["bug", "ui"])

        let task = router.postJSON(session, expectedResultType: [String: Any].self, completion: outcome.recordJSON)

        #expect(task != nil)
        let request = try #require(session.uploadRequests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/hello/issues")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic c2VjcmV0")
        let body = try #require(session.uploadBodies.first ?? nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["title"] as? String == "Crash")
        #expect(json["body"] as? String == "Steps")
        #expect(json["assignee"] as? String == "octocat")
        #expect(json["labels"] as? [String] == ["bug", "ui"])
        #expect(outcome.calls == 1)
        #expect(outcome.jsonObject?["id"] as? Int == 7)
        #expect(outcome.error == nil)
    }

    @Test
    func postJSONBodyOnlyHasProvidedPatchFields() throws {
        let session = FakeGitSession(status: 200, body: "{}")
        let router = GitHubIssueRouter.patchIssue(configuration, "o", "r", 3, nil, "new body", nil, .closed)

        _ = router.postJSON(session, expectedResultType: [String: Any].self) { _, _ in }

        let body = try #require(session.uploadBodies.first ?? nil)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["body": "new body", "state": "closed"])
        #expect(session.uploadRequests.first?.url?.absoluteString == "https://api.github.com/repos/o/r/issues/3")
    }

    @Test
    func postJSONMapsJSONErrorBodiesIntoErrorKey() throws {
        let session = FakeGitSession(status: 422, body: #"{"message":"Validation Failed"}"#)
        let outcome = GitCallOutcome<Data>()

        _ = GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")
            .postJSON(session, expectedResultType: [String: Any].self, completion: outcome.recordJSON)

        let error = try #require(outcome.error.map { $0 as NSError })
        #expect(error.domain == "com.dreamder.models.accounts.github")
        #expect(error.code == 422)
        #expect((error.userInfo["ErrorKey"] as? [String: Any])?["message"] as? String == "Validation Failed")
        #expect(outcome.value == nil)
    }

    @Test
    func postJSONKeepsNonJSONErrorBodiesAsStrings() throws {
        let session = FakeGitSession(status: 502, body: "Bad gateway")
        let outcome = GitCallOutcome<Data>()

        _ = GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")
            .postJSON(session, expectedResultType: [String: Any].self, completion: outcome.recordJSON)

        let error = try #require(outcome.error.map { $0 as NSError })
        #expect(error.code == 502)
        #expect(error.userInfo["ErrorKey"] as? String == "Bad gateway")
    }

    @Test
    func postJSONReturnsNilForAnInvalidEndpointWithoutUploading() {
        let session = FakeGitSession()
        let outcome = GitCallOutcome<Data>()
        let broken = GitHubTokenConfiguration("secret", url: "")

        let task = GitHubIssueRouter.commentIssue(broken, "o", "r", 1, "hi")
            .postJSON(session, expectedResultType: [String: Any].self, completion: outcome.recordJSON)

        #expect(task == nil)
        #expect(session.requestCount == 0)
        #expect(outcome.calls == 0)
    }

    @Test
    func postDecodesCodableResponses() throws {
        let session = FakeGitSession(status: 201, body: #"{"id":11,"name":"made"}"#)
        let outcome = GitCallOutcome<GitTestPayload>()

        _ = GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")
            .post(session, expectedResultType: GitTestPayload.self, completion: outcome.record)

        #expect(outcome.value == GitTestPayload(id: 11, name: "made"))
        let body = try #require(session.uploadBodies.first ?? nil)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["body": "hi"])
    }

    @Test
    func postMapsFailureStatusToNSError() throws {
        let session = FakeGitSession(status: 401, body: #"{"message":"Bad credentials"}"#)
        let outcome = GitCallOutcome<GitTestPayload>()

        _ = GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")
            .post(session, expectedResultType: GitTestPayload.self, completion: outcome.record)

        let error = try #require(outcome.error.map { $0 as NSError })
        #expect(error.code == 401)
        #expect((error.userInfo["ErrorKey"] as? [String: Any])?["message"] as? String == "Bad credentials")
    }

    @Test
    func asyncPostJSONUploadsAndReturnsTheParsedObject() async throws {
        let session = FakeGitSession(status: 201, body: #"{"id":3}"#)
        let router = GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")

        let result: [String: Any]? = try await router.postJSON(session, expectedResultType: [String: Any].self)

        #expect(result?["id"] as? Int == 3)
        #expect(session.uploadRequests.first?.url?.absoluteString == "https://api.github.com/repos/o/r/issues/1/comments")
    }

    @Test
    func asyncPostJSONThrowsMinus876ForAnInvalidEndpoint() async {
        let session = FakeGitSession()
        let broken = GitHubTokenConfiguration("secret", url: "")

        do {
            let _: [String: Any]? = try await GitHubIssueRouter.commentIssue(broken, "o", "r", 1, "hi")
                .postJSON(session, expectedResultType: [String: Any].self)
            Issue.record("expected a throw")
        } catch {
            #expect((error as NSError).code == -876)
            #expect((error as NSError).domain == "com.dreamder.models.accounts.github")
        }
        #expect(session.requestCount == 0)
    }

    @Test
    func asyncPostJSONThrowsForHTTPFailures() async {
        let session = FakeGitSession(status: 422, body: "nope")

        do {
            let _: [String: Any]? = try await GitHubIssueRouter.commentIssue(configuration, "o", "r", 1, "hi")
                .postJSON(session, expectedResultType: [String: Any].self)
            Issue.record("expected a throw")
        } catch {
            let nsError = error as NSError
            #expect(nsError.code == 422)
            #expect(nsError.userInfo["ErrorKey"] as? String == "nope")
        }
    }
}
