import Foundation
import LanguageServerProtocol
import Synchronization

nonisolated final class LSPDynamicCapabilityRegistry: Sendable {
    private let storage = Mutex<[String: [Registration]]>([:])

    init() {}

    func register(_ registrations: [Registration]) {
        storage.withLock { methods in
            for registration in registrations {
                var existing = methods[registration.method] ?? []
                if let index = existing.firstIndex(where: { $0.id == registration.id }) {
                    existing[index] = registration
                } else {
                    existing.append(registration)
                }
                methods[registration.method] = existing
            }
        }
    }

    func unregister(_ unregistrations: [Unregistration]) {
        storage.withLock { methods in
            for unregistration in unregistrations {
                guard var existing = methods[unregistration.method] else { continue }
                existing.removeAll { $0.id == unregistration.id }
                methods[unregistration.method] = existing.isEmpty ? nil : existing
            }
        }
    }

    func removeAll() {
        storage.withLock { $0.removeAll() }
    }

    func hasCapability(_ method: String) -> Bool {
        storage.withLock { $0[method] != nil }
    }

    func registrations(for method: String) -> [Registration] {
        storage.withLock { $0[method] ?? [] }
    }

    var registeredMethods: [String] {
        storage.withLock { $0.keys.sorted() }
    }

    func registerOptions<Options: Decodable>(for method: String, as type: Options.Type) -> [Options] {
        registrations(for: method).compactMap { registration in
            guard let options = registration.registerOptions,
                  let data = try? JSONEncoder().encode(options) else {
                return nil
            }
            return try? JSONDecoder().decode(type, from: data)
        }
    }
}

nonisolated enum LSPRefreshKind: String, Sendable, CaseIterable {
    case semanticTokens
    case inlayHint
    case diagnostics

    init?(refreshMethod: String) {
        switch refreshMethod {
        case "workspace/semanticTokens/refresh":
            self = .semanticTokens
        case "workspace/inlayHint/refresh":
            self = .inlayHint
        case "workspace/diagnostic/refresh":
            self = .diagnostics
        default:
            return nil
        }
    }

    init?(registrationMethod: String) {
        switch registrationMethod {
        case "textDocument/inlayHint":
            self = .inlayHint
        case "textDocument/diagnostic":
            self = .diagnostics
        default:
            return nil
        }
    }
}
