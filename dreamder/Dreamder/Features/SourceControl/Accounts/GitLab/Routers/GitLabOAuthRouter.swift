//
//  GitLabOAuthRouter.swift
//  DreamderModules/GitAccounts
//
//  Created by Nanashi Li on 2022/03/31.
//

import Foundation

enum GitLabOAuthRouter: GitRouter {
    case authorize(GitLabOAuthConfiguration, String)
    case accessToken(GitLabOAuthConfiguration, String, String)

    var configuration: GitRouterConfiguration? {
        switch self {
        case .authorize(let config, _): return config
        case .accessToken(let config, _, _): return config
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
            return "oauth/authorize"
        case .accessToken:
            return "oauth/token"
        }
    }

    var params: [String: Any] {
        switch self {
        case let .authorize(config, redirectURI):
            return [
                "client_id": config.token as AnyObject,
                "response_type": "code" as AnyObject,
                "redirect_uri": redirectURI as AnyObject]
        case let .accessToken(config, code, rediredtURI):
            return [
                "client_id": config.token as AnyObject,
                "client_secret": config.secret as AnyObject,
                "code": code as AnyObject, "grant_type":
                    "authorization_code" as AnyObject,
                "redirect_uri": rediredtURI as AnyObject]
        }
    }

    var URLRequest: Foundation.URLRequest? {
        let config: GitLabOAuthConfiguration
        switch self {
        case .authorize(let value, _): config = value
        case .accessToken(let value, _, _): config = value
        }
        guard let base = config.webEndpoint.flatMap({ URL(string: $0) }),
              let url = URL(string: path, relativeTo: base),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        return request(components, parameters: params)
    }
}
