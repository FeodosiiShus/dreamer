import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceTrust {
    static let defaultsKey = "dreamder.workspaceTrust.trustedRoots"
    static let shared = WorkspaceTrust()

    private(set) var trustedRoots: [String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let confirm: @MainActor (URL) async -> Bool

    init(
        defaults: UserDefaults = .standard,
        confirm: @escaping @MainActor (URL) async -> Bool = WorkspaceTrust.askUser
    ) {
        self.defaults = defaults
        self.confirm = confirm
        self.trustedRoots = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func isTrusted(_ root: URL?) -> Bool {
        guard let root else { return false }
        let path = Self.normalizedPath(root)
        return trustedRoots.contains { Self.path(path, isWithin: $0) }
    }

    func trust(_ root: URL) {
        let path = Self.normalizedPath(root)
        guard !trustedRoots.contains(path) else { return }
        trustedRoots.append(path)
        trustedRoots.sort()
        persist()
    }

    func revoke(_ root: URL) {
        let path = Self.normalizedPath(root)
        let remaining = trustedRoots.filter { !Self.path($0, isWithin: path) }
        guard remaining.count != trustedRoots.count else { return }
        trustedRoots = remaining
        persist()
    }

    func requestTrust(for root: URL?) async -> Bool {
        guard let root else { return false }
        if isTrusted(root) { return true }
        guard await confirm(root) else { return false }
        trust(root)
        return true
    }

    private func persist() {
        defaults.set(trustedRoots, forKey: Self.defaultsKey)
    }

    nonisolated static func normalizedPath(_ root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    nonisolated static func path(_ path: String, isWithin ancestor: String) -> Bool {
        if path == ancestor { return true }
        return path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    static func makeAlert(for root: URL) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Trust and Open Project \u{2018}\(root.lastPathComponent)\u{2019}?"
        alert.informativeText = """
        Dreamder provides features that may execute potentially malicious code from this folder, \
        such as language servers and project tools. If you don\u{2019}t trust the source, stay in \
        Safe Mode to only browse its code.
        """
        alert.addButton(withTitle: "Trust Project")
        alert.addButton(withTitle: "Don't Trust")
        return alert
    }

    static func presentAlert(for root: URL, run: (NSAlert) -> NSApplication.ModalResponse) -> Bool {
        run(makeAlert(for: root)) == .alertFirstButtonReturn
    }

    static func askUser(about root: URL) -> Bool {
        presentAlert(for: root) { runAlert($0, headless: DreamderHeadless.isEnabled) }
    }

    static func runAlert(_ alert: NSAlert, headless: Bool) -> NSApplication.ModalResponse {
        headless ? .abort : alert.runModal()
    }
}
