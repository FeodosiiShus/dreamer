//
//  GitHubConfiguration.swift
//  DreamderModules/GitAccounts
//
//  Created by Nanashi Li on 2022/03/31.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct GitHubTokenConfiguration: GitRouterConfiguration {
    let provider = SourceControlAccount.Provider.github
    var apiEndpoint: String?
    var accessToken: String?
    let errorDomain: String? = "com.dreamder.models.accounts.github"
    let authorizationHeader: String? = "Basic"

    /// Custom `Accept` header for API previews.
    ///
    /// Used for preview support of new APIs, for instance Reaction API.
    /// see: https://developer.github.com/changes/2016-05-12-reactions-api-preview/
    private var previewCustomHeaders: [GitHTTPHeader]?

    var customHeaders: [GitHTTPHeader]? {
        /// More (non-preview) headers can be appended if needed in the future
        return previewCustomHeaders
    }

    init(_ token: String? = nil, url: String? = nil, previewHeaders: [GitHubPreviewHeader] = []) {
        apiEndpoint = url ?? provider.apiURL?.absoluteString
        accessToken = token.map { Data($0.utf8).base64EncodedString() }
        previewCustomHeaders = previewHeaders.map { $0.header }
    }
}

nonisolated struct GitHubOAuthConfiguration: GitRouterConfiguration {
    let provider = SourceControlAccount.Provider.github
    var apiEndpoint: String?
    var accessToken: String?
    let token: String
    let secret: String
    let scopes: [String]
    let webEndpoint: String?
    let errorDomain = "com.dreamder.models.accounts.github"

    /// Custom `Accept` header for API previews.
    ///
    /// Used for preview support of new APIs, for instance Reaction API.
    /// see: https://developer.github.com/changes/2016-05-12-reactions-api-preview/
    private var previewCustomHeaders: [GitHTTPHeader]?

    var customHeaders: [GitHTTPHeader]? {
        /// More (non-preview) headers can be appended if needed in the future
        return previewCustomHeaders
    }

    init(
        _ url: String? = nil,
        webURL: String? = nil,
        token: String,
        secret: String,
        scopes: [String],
        previewHeaders: [GitHubPreviewHeader] = []
    ) {
        apiEndpoint = url ?? provider.apiURL?.absoluteString
        webEndpoint = webURL ?? provider.baseURL?.absoluteString
        self.token = token
        self.secret = secret
        self.scopes = scopes
        previewCustomHeaders = previewHeaders.map { $0.header }
    }

    func authenticate() -> URL? {
        GitHubOAuthRouter.authorize(self).URLRequest?.url
    }

    func authorize(
        _ session: GitURLSession = URLSession.shared,
        code: String,
        completion: @escaping @Sendable (_ config: GitHubTokenConfiguration) -> Void
    ) {
        let request = GitHubOAuthRouter.accessToken(self, code).URLRequest
        if let request {
            let task = session.dataTask(with: request) { data, response, _ in
                if let response = response as? HTTPURLResponse {
                    if response.statusCode != 200 {
                        return
                    } else {
                        if let data,
                           let string = String(bytes: data, encoding: .utf8) {
                            let accessToken = self.accessTokenFromResponse(string)
                            if let accessToken {
                                let config = GitHubTokenConfiguration(accessToken, url: self.apiEndpoint ?? "")
                                completion(config)
                            }
                        }
                    }
                }
            }
            task.resume()
        }
    }

    func handleOpenURL(
        _ session: GitURLSession = URLSession.shared,
        url: URL,
        completion: @escaping @Sendable (_ config: GitHubTokenConfiguration) -> Void
    ) {

        if let code = url.URLParameters["code"] {
            authorize(session, code: code) { config in
                completion(config)
            }
        }
    }

    func accessTokenFromResponse(_ response: String) -> String? {
        let accessTokenParam = response.components(separatedBy: "&").first
        if let accessTokenParam {
            return accessTokenParam.components(separatedBy: "=").last
        }
        return nil
    }
}

nonisolated enum GitHubOAuthRouter: GitRouter {
    case authorize(GitHubOAuthConfiguration)
    case accessToken(GitHubOAuthConfiguration, String)

    var configuration: GitRouterConfiguration? {
        switch self {
        case let .authorize(config): return config
        case let .accessToken(config, _): return config
        }
    }

    var method: GitHTTPMethod {
        switch self {
        case .authorize:
            return .GET
        case .accessToken:
            return .POST
        }
    }

    var encoding: GitHTTPEncoding {
        switch self {
        case .authorize:
            return .url
        case .accessToken:
            return .form
        }
    }

    var path: String {
        switch self {
        case .authorize:
            return "login/oauth/authorize"
        case .accessToken:
            return "login/oauth/access_token"
        }
    }

    var params: [String: Any] {
        switch self {
        case let .authorize(config):
            let scope = (config.scopes as NSArray).componentsJoined(by: ",")
            return ["scope": scope, "client_id": config.token, "allow_signup": "false"]
        case let .accessToken(config, code):
            return ["client_id": config.token, "client_secret": config.secret, "code": code]
        }
    }

    #if canImport(FoundationNetworking)
    typealias FoundationURLRequestType = FoundationNetworking.URLRequest
    #else
    typealias FoundationURLRequestType = Foundation.URLRequest
    #endif

    var URLRequest: FoundationURLRequestType? {
        let config: GitHubOAuthConfiguration
        switch self {
        case let .authorize(value): config = value
        case let .accessToken(value, _): config = value
        }
        guard let base = config.webEndpoint.flatMap({ URL(string: $0) }),
              let url = URL(string: path, relativeTo: base),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        return request(components, parameters: params)
    }
}
