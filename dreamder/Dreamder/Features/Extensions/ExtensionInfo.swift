//
//  ExtensionInfo.swift
//  Dreamder
//
//  Created by Wouter Hennen on 31/12/2022.
//

import AppKit
import CodeEditKit
import ExtensionFoundation

struct ExtensionInfo: Identifiable, Hashable {

    let endpoint: AppExtensionIdentity

    let availableFeatures: [ExtensionKind]

    let isDebug: Bool

    var bundleURL: URL

    var bundle: Bundle?

    var pid: Int32

    var id: String {
        endpoint.bundleIdentifier
    }

    var name: String {
        endpoint.localizedName
    }

    var version: String? {
        bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func restart() {
        kill(pid, SIGKILL)
    }

    init(endpoint: AppExtensionIdentity) async throws {
        let details = try await ExtensionInfo.loadDetails(for: endpoint)
        try self.init(endpoint: endpoint, details: details)
    }

    init(endpoint: AppExtensionIdentity, details: Details) throws {
        self.endpoint = endpoint
        self.pid = details.pid
        self.isDebug = details.isDebug
        self.availableFeatures = try JSONDecoder().decode([ExtensionKind].self, from: details.encodedFeatures)
        self.bundleURL = try JSONDecoder().decode(URL.self, from: details.encodedBundleURL)
        self.bundle = Bundle(url: bundleURL)
    }
}

extension ExtensionInfo {
    nonisolated struct Details: Sendable {
        let pid: pid_t
        let isDebug: Bool
        let encodedFeatures: Data
        let encodedBundleURL: Data
    }

    @concurrent
    static func loadDetails(for endpoint: AppExtensionIdentity) async throws -> Details {
        let process = try await AppExtensionProcess(configuration: .init(appExtensionIdentity: endpoint))

        let connection = try process.makeXPCConnection()
        connection.remoteObjectInterface = .init(with: XPCWrappable.self)
        connection.resume()

        defer {
            connection.invalidate()
        }

        return Details(
            pid: try await getProcessID(connection),
            isDebug: try await getDebugState(connection),
            encodedFeatures: try await getEncodedFeatures(connection),
            encodedBundleURL: try await getEncodedBundleURL(connection)
        )
    }

    @concurrent
    private static func getProcessID(_ connection: NSXPCConnection) async throws -> pid_t {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionProcessIdentifier {
                continuation.resumingHandler($0, .none)
            }
        }
    }

    @concurrent
    private static func getDebugState(_ connection: NSXPCConnection) async throws -> Bool {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.isDebug {
                continuation.resumingHandler($0, .none)
            }
        }
    }

    @concurrent
    private static func getEncodedFeatures(_ connection: NSXPCConnection) async throws -> Data {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionKinds(reply: Self.dataHandler(for: continuation))
        }
    }

    @concurrent
    private static func getEncodedBundleURL(_ connection: NSXPCConnection) async throws -> Data {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionURL(reply: Self.dataHandler(for: continuation))
        }
    }

    private nonisolated static func dataHandler(for continuation: CheckedContinuation<Data, Error>) -> XPCReply {
        { data, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: ExtensionReplyError.missingValue)
            }
        }
    }

    private nonisolated enum ExtensionReplyError: Error {
        case missingValue
    }
}

extension ExtensionInfo {
    /// Bundle identifier of parent app
    var parentBundleIdentifier: String {
        endpoint.bundleIdentifier.split(separator: ".").dropLast().joined(separator: ".")
    }

    var lastPathOfBundleIdentifier: String {
        endpoint.bundleIdentifier.split(separator: ".").last.map(String.init) ?? endpoint.bundleIdentifier
    }

    /// Icon of appex folder
    public var icon: NSImage? {
        // TODO: Use icon of extension instead of parent app
        // A way to get the path of an .appex file should be used.
        // Unfortunately, NSWorkspace.shared.urlForApplication only seems to work for .app
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parentBundleIdentifier)
        guard let path else { return nil }

        return NSWorkspace.shared.icon(forFile: path.path)
    }
}
