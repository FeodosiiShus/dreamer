import CodeEditSourceEditor
import Foundation

nonisolated struct EditorPlace: Hashable, Sendable {
    nonisolated struct Caret: Hashable, Sendable {
        let line: Int
        let column: Int
    }

    static let mergeDistance = 4

    let fileURL: URL
    let carets: [Caret]

    init(fileURL: URL, carets: [Caret]) {
        self.fileURL = fileURL.standardizedFileURL
        self.carets = carets
    }

    init(fileURL: URL, line: Int, column: Int) {
        self.init(fileURL: fileURL, carets: [Caret(line: line, column: column)])
    }

    init(fileURL: URL, positions: [CursorPosition]) {
        let carets = positions.map { Caret(line: max($0.start.line, 1), column: max($0.start.column, 1)) }
        self.init(fileURL: fileURL, carets: carets.isEmpty ? [Caret(line: 1, column: 1)] : carets)
    }

    var line: Int { carets.first?.line ?? 1 }

    var column: Int { carets.first?.column ?? 1 }

    func isSame(as other: EditorPlace) -> Bool {
        guard fileURL == other.fileURL, carets.count == other.carets.count else { return false }
        return zip(carets, other.carets).allSatisfy { abs($0.line - $1.line) < Self.mergeDistance }
    }
}

nonisolated struct EditorLocationHistory: Sendable {
    static let defaultStackLimit = 150
    static let recentLocationsLimit = 25

    private(set) var backPlaces: [EditorPlace] = []
    private(set) var forwardPlaces: [EditorPlace] = []
    private(set) var changePlaces: [EditorPlace] = []

    private let backLimit: Int
    private let changeLimit: Int
    private let isFileValid: @Sendable (URL) -> Bool

    init(
        backLimit: Int = EditorLocationHistory.defaultStackLimit,
        changeLimit: Int = EditorLocationHistory.defaultStackLimit,
        isFileValid: @escaping @Sendable (URL) -> Bool = EditorLocationHistory.fileExists
    ) {
        self.backLimit = backLimit
        self.changeLimit = changeLimit
        self.isFileValid = isFileValid
    }

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    var isBackAvailable: Bool { !backPlaces.isEmpty }

    var isForwardAvailable: Bool { !forwardPlaces.isEmpty }

    mutating func recordBackPlace(_ place: EditorPlace) {
        Self.putLastOrMerge(place, into: &backPlaces, limit: backLimit)
        forwardPlaces.removeAll()
        removeInvalidPlaces()
    }

    mutating func recordChangePlace(_ place: EditorPlace) {
        Self.putLastOrMerge(place, into: &changePlaces, limit: changeLimit)
    }

    mutating func back(from current: EditorPlace?) -> EditorPlace? {
        removeInvalidPlaces()
        guard let target = backPlaces.popLast() else { return nil }
        if let current {
            forwardPlaces.append(current)
        }
        removeInvalidPlaces()
        return target
    }

    mutating func forward(from current: EditorPlace?) -> EditorPlace? {
        removeInvalidPlaces()
        guard var target = forwardPlaces.popLast() else { return nil }
        if let current {
            while !forwardPlaces.isEmpty && current.isSame(as: target) {
                target = forwardPlaces.removeLast()
            }
            Self.putLastOrMerge(current, into: &backPlaces, limit: backLimit)
        }
        removeInvalidPlaces()
        return target
    }

    mutating func removeInvalidPlaces() {
        var validity: [URL: Bool] = [:]
        let check = isFileValid
        func isValid(_ place: EditorPlace) -> Bool {
            if let known = validity[place.fileURL] {
                return known
            }
            let result = check(place.fileURL)
            validity[place.fileURL] = result
            return result
        }
        backPlaces.removeAll { !isValid($0) }
        forwardPlaces.removeAll { !isValid($0) }
        changePlaces.removeAll { !isValid($0) }
    }

    mutating func removeBackPlaces(sameAs place: EditorPlace) {
        backPlaces.removeAll { $0.isSame(as: place) }
    }

    mutating func removeChangePlaces(sameAs place: EditorPlace) {
        changePlaces.removeAll { $0.isSame(as: place) }
    }

    func recentPlaces(changed: Bool, limit: Int = EditorLocationHistory.recentLocationsLimit) -> [EditorPlace] {
        var result: [EditorPlace] = []
        for place in (changed ? changePlaces : backPlaces).reversed() {
            if !result.contains(where: { place.isSame(as: $0) }) {
                result.append(place)
            }
            if result.count >= limit {
                break
            }
        }
        return result
    }

    private static func putLastOrMerge(_ next: EditorPlace, into places: inout [EditorPlace], limit: Int) {
        if let previous = places.last, previous.isSame(as: next) {
            places.removeLast()
        }
        places.append(next)
        if places.count > limit {
            places.removeFirst()
        }
    }
}
