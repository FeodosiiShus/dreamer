import AppKit
import CodeEditTextView
import Foundation

nonisolated struct FindReplaceEdit: Sendable, Equatable {
    let range: NSRange
    let replacement: String
}

nonisolated struct FindReplaceJob: Sendable {
    let url: URL
    let ranges: [NSRange]
    let model: FindModel
    let regex: NSRegularExpression
}

nonisolated struct FindReplaceResult: Sendable, Equatable {
    let text: String
    let applied: [FindReplaceEdit]
    let missing: Int
}

nonisolated enum FindReplaceOutcome: Sendable, Equatable {
    case replaced(FindReplaceResult)
    case stale
    case failed(String)

    var isClean: Bool {
        if case .replaced(let result) = self {
            return result.missing == 0
        }
        return false
    }
}

nonisolated enum FindReplaceEngine {
    static func edits(
        for job: FindReplaceJob,
        in text: String
    ) -> (edits: [FindReplaceEdit], missing: Int) {
        let wanted = Set(job.ranges)
        let source = text as NSString
        var edits: [FindReplaceEdit] = []
        for match in job.model.findMatches(in: text, using: job.regex) where wanted.contains(match.range) {
            guard let replacement = try? job.model.replacement(for: match, in: source, using: job.regex) else {
                continue
            }
            edits.append(FindReplaceEdit(range: match.range, replacement: replacement))
        }
        return (edits, wanted.count - edits.count)
    }

    static func apply(_ edits: [FindReplaceEdit], to text: String) -> String {
        let source = text as NSString
        var output = ""
        var cursor = 0
        for edit in edits {
            output += source.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            output += edit.replacement
            cursor = NSMaxRange(edit.range)
        }
        output += source.substring(from: cursor)
        return output
    }

    static func delta(before location: Int, applied: [FindReplaceEdit]) -> Int {
        applied
            .filter { NSMaxRange($0.range) <= location }
            .reduce(0) { $0 + ($1.replacement as NSString).length - $1.range.length }
    }

    static func mapped(_ range: NSRange, through edits: [FindReplaceEdit]) -> NSRange {
        let start = mapped(range.location, through: edits)
        let end = mapped(NSMaxRange(range), through: edits)
        return NSRange(location: start, length: end - start)
    }

    private static func mapped(_ offset: Int, through edits: [FindReplaceEdit]) -> Int {
        if let enclosing = edits.first(where: { $0.range.location < offset && offset < NSMaxRange($0.range) }) {
            let before = delta(before: enclosing.range.location, applied: edits)
            return enclosing.range.location + before + (enclosing.replacement as NSString).length
        }
        return offset + delta(before: offset, applied: edits)
    }
}

nonisolated enum FindFileRewriter {
    typealias Writer = @Sendable (FileHandle, Data) throws -> Void

    private struct NotWritable: LocalizedError {
        var errorDescription: String? { "The file is read-only." }
    }

    static let defaultWriter: Writer = { handle, data in try handle.write(contentsOf: data) }

    static func rewrite(_ job: FindReplaceJob, writer: Writer = FindFileRewriter.defaultWriter) -> FindReplaceOutcome {
        let target = job.url.resolvingSymlinksInPath()
        guard let original = try? Data(contentsOf: target),
              let text = String(data: original, encoding: .utf8) else {
            return .failed("Cannot read \(job.url.lastPathComponent)")
        }
        let (edits, missing) = FindReplaceEngine.edits(for: job, in: text)
        guard !edits.isEmpty else { return .stale }
        let updated = FindReplaceEngine.apply(edits, to: text)
        do {
            guard try replace(target, expecting: original, with: Data(updated.utf8), writer: writer) else {
                return .stale
            }
        } catch {
            return .failed("Cannot write \(job.url.lastPathComponent): \(error.localizedDescription)")
        }
        return .replaced(FindReplaceResult(text: updated, applied: edits, missing: missing))
    }

    private static func replace(_ url: URL, expecting original: Data, with data: Data, writer: Writer) throws -> Bool {
        guard FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false)) else {
            throw NotWritable()
        }
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).replace")
        try Data().write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try writer(handle, data)
            try handle.synchronize()
        }
        guard (try? Data(contentsOf: url)) == original else { return false }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        return true
    }

    @concurrent
    static func rewrite(_ jobs: [FindReplaceJob]) async -> [FindReplaceOutcome] {
        await withTaskGroup(of: (Int, FindReplaceOutcome).self) { group in
            var pending = jobs.enumerated().makeIterator()
            let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
            for _ in 0..<width {
                guard let (index, job) = pending.next() else { break }
                group.addTask { (index, rewrite(job)) }
            }
            var outcomes = [FindReplaceOutcome](repeating: .stale, count: jobs.count)
            for await (index, outcome) in group {
                outcomes[index] = outcome
                if let (next, job) = pending.next() {
                    group.addTask { (next, rewrite(job)) }
                }
            }
            return outcomes
        }
    }
}

@MainActor
enum FindBufferReplacer {
    static func apply(_ job: FindReplaceJob, to document: CodeFileDocument) -> FindReplaceOutcome {
        let textView = document.attachedTextView
        guard let storage = document.content, !document.isReadOnly, textView?.isEditable ?? true else {
            return .failed("\(job.url.lastPathComponent) is read-only")
        }
        let (edits, missing) = FindReplaceEngine.edits(for: job, in: storage.string)
        guard !edits.isEmpty else { return .stale }

        if let textView, textView.textStorage === storage {
            let undoManager = textView.undoManager
            let selections = textView.selectionManager.textSelections.map(\.range)
            undoManager?.beginUndoGrouping()
            for edit in edits.reversed() {
                textView.replaceCharacters(in: edit.range, with: edit.replacement, skipUpdateSelection: true)
            }
            undoManager?.endUndoGrouping()
            textView.selectionManager.setSelectedRanges(
                selections.map { FindReplaceEngine.mapped($0, through: edits) }
            )
        } else {
            storage.beginEditing()
            for edit in edits.reversed() {
                storage.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            storage.endEditing()
            document.updateChangeCount(.changeDone)
        }
        return .replaced(FindReplaceResult(text: storage.string, applied: edits, missing: missing))
    }
}
