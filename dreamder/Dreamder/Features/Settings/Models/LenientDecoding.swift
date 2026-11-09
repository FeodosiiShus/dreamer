import Foundation

extension KeyedDecodingContainer {
    nonisolated func lenient<Value: Decodable>(_ key: Key, default fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }

    nonisolated func lenientOptional<Value: Decodable>(_ key: Key) -> Value? {
        try? decodeIfPresent(Value.self, forKey: key)
    }
}
