//
//  LSPCache.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation

class LSPCache {
    static let capacity = 2048

    private var entries: [String: CacheEntry] = [:]
    private var insertionOrder: [String] = []
    private var keysByURI: [String: Set<String>] = [:]

    func get<T: Codable & Sendable>(key: CacheKey, as type: T.Type) -> T? {
        entries[key.description]?.getValue(as: type)
    }

    func set<T: Codable & Sendable>(key: CacheKey, value: T) {
        let description = key.description
        if entries.updateValue(CacheEntry(value), forKey: description) != nil {
            insertionOrder.removeAll { $0 == description }
        }
        insertionOrder.append(description)
        keysByURI[key.uri, default: []].insert(description)
        evictOverflow()
    }

    func invalidate(key: CacheKey) {
        let description = key.description
        remove(description)
        keysByURI[key.uri]?.remove(description)
    }

    func invalidate(uri: String) {
        guard let keys = keysByURI.removeValue(forKey: uri) else { return }
        for key in keys {
            remove(key)
        }
    }

    private func remove(_ description: String) {
        guard entries.removeValue(forKey: description) != nil else { return }
        insertionOrder.removeAll { $0 == description }
    }

    private func evictOverflow() {
        while insertionOrder.count > Self.capacity {
            let oldest = insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)
            for uri in keysByURI.keys {
                keysByURI[uri]?.remove(oldest)
            }
        }
    }

    final class CacheEntry: NSObject {
        let value: Any
        let type: Any.Type

        init<T: Codable & Sendable>(_ value: T) {
            self.value = value
            self.type = T.self
        }

        func getValue<T: Codable & Sendable>(as type: T.Type) -> T? {
            return value as? T
        }
    }
}

extension CacheKey: CustomStringConvertible {
    var description: String {
        var parts = [uri, requestType]
        if let position {
            parts.append("\(position.line):\(position.character)")
        }
        if let documentVersion {
            parts.append("v\(documentVersion)")
        }
        if let extraData {
            parts.append("\(extraData)")
        }
        return parts.joined(separator: "|")
    }
}
