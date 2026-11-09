import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceTrustTests {
    @MainActor
    private final class ConfirmRecorder {
        var asked: [URL] = []
        let answer: Bool

        init(answer: Bool) {
            self.answer = answer
        }

        func confirm(_ root: URL) async -> Bool {
            asked.append(root)
            return answer
        }
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func makeTrust(
        _ defaults: UserDefaults,
        answer: Bool = false,
        recorder: ConfirmRecorder? = nil
    ) -> WorkspaceTrust {
        let recorder = recorder ?? ConfirmRecorder(answer: answer)
        return WorkspaceTrust(defaults: defaults, confirm: { await recorder.confirm($0) })
    }

    @Test
    func trustedRootsPersistAcrossInstances() throws {
        try withIsolatedDefaults { defaults in
            let first = makeTrust(defaults)
            #expect(first.trustedRoots.isEmpty)
            first.trust(url("/projects/beta"))
            first.trust(url("/projects/alpha"))
            first.trust(url("/projects/beta"))

            #expect(first.trustedRoots == ["/projects/alpha", "/projects/beta"])
            #expect(defaults.stringArray(forKey: WorkspaceTrust.defaultsKey) == ["/projects/alpha", "/projects/beta"])

            let second = makeTrust(defaults)
            #expect(second.isTrusted(url("/projects/alpha")))
            #expect(second.isTrusted(url("/projects/beta")))
            #expect(!second.isTrusted(url("/projects/gamma")))
        }
    }

    @Test
    func aRootIsTrustedWhenItOrAnAncestorIsTrusted() throws {
        try withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults)
            trust.trust(url("/projects/app"))

            #expect(trust.isTrusted(url("/projects/app")))
            #expect(trust.isTrusted(url("/projects/app/packages/web")))
            #expect(trust.isTrusted(url("/projects/app/")))
            #expect(!trust.isTrusted(url("/projects/application")))
            #expect(!trust.isTrusted(url("/projects")))
            #expect(!trust.isTrusted(url("/")))
        }
    }

    @Test
    func aMissingRootIsNeverTrusted() throws {
        try withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults)
            trust.trust(url("/projects/app"))
            #expect(!trust.isTrusted(nil))
            #expect(!WorkspaceTrust.shared.isTrusted(nil))
        }
    }

    @Test
    func revokingRemovesTheRootAndEverythingTrustedBelowIt() throws {
        try withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults)
            trust.trust(url("/projects/app"))
            trust.trust(url("/projects/app/packages/web"))
            trust.trust(url("/projects/other"))

            trust.revoke(url("/projects/app"))

            #expect(trust.trustedRoots == ["/projects/other"])
            #expect(!trust.isTrusted(url("/projects/app/packages/web")))
            #expect(makeTrust(defaults).trustedRoots == ["/projects/other"])

            trust.revoke(url("/projects/unknown"))
            #expect(trust.trustedRoots == ["/projects/other"])
        }
    }

    @Test
    func revokingAChildKeepsTheTrustedAncestor() throws {
        try withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults)
            trust.trust(url("/projects/app"))

            trust.revoke(url("/projects/app/packages/web"))

            #expect(trust.isTrusted(url("/projects/app/packages/web")))
        }
    }

    @Test
    func pathsAreStandardizedBeforeComparison() throws {
        try withTempDir { directory in
            try withIsolatedDefaults { defaults in
                let real = directory.appending(path: "real")
                try FileManager.default.createDirectory(
                    at: real.appending(path: "nested"),
                    withIntermediateDirectories: true
                )
                let link = directory.appending(path: "link")
                try FileManager.default.createSymbolicLink(
                    atPath: link.path(percentEncoded: false),
                    withDestinationPath: real.path(percentEncoded: false)
                )
                let trust = makeTrust(defaults)
                trust.trust(link)

                #expect(trust.isTrusted(real))
                #expect(trust.isTrusted(directory.appending(path: "real/./nested/../nested")))
                #expect(WorkspaceTrust.normalizedPath(url("/")) == "/")
                #expect(WorkspaceTrust.path("/anything", isWithin: "/"))
                #expect(!WorkspaceTrust.path("/anything", isWithin: "/other"))
            }
        }
    }

    @Test
    func requestingTrustForAMissingRootNeverAsks() async throws {
        let recorder = ConfirmRecorder(answer: true)
        try await withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults, recorder: recorder)
            #expect(await trust.requestTrust(for: nil) == false)
            #expect(recorder.asked.isEmpty)
        }
    }

    @Test
    func requestingTrustForATrustedRootDoesNotAskAgain() async throws {
        let recorder = ConfirmRecorder(answer: false)
        try await withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults, recorder: recorder)
            trust.trust(url("/projects/app"))

            #expect(await trust.requestTrust(for: url("/projects/app/sub")))
            #expect(recorder.asked.isEmpty)
        }
    }

    @Test
    func confirmingPersistsTheTrust() async throws {
        let recorder = ConfirmRecorder(answer: true)
        try await withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults, recorder: recorder)

            #expect(await trust.requestTrust(for: url("/projects/app")))
            #expect(recorder.asked.map(\.path) == ["/projects/app"])
            #expect(trust.isTrusted(url("/projects/app")))
            #expect(makeTrust(defaults).isTrusted(url("/projects/app")))
        }
    }

    @Test
    func decliningLeavesTheRootUntrusted() async throws {
        let recorder = ConfirmRecorder(answer: false)
        try await withIsolatedDefaults { defaults in
            let trust = makeTrust(defaults, recorder: recorder)

            #expect(await trust.requestTrust(for: url("/projects/app")) == false)
            #expect(recorder.asked.count == 1)
            #expect(!trust.isTrusted(url("/projects/app")))
            #expect(makeTrust(defaults).trustedRoots.isEmpty)
        }
    }

    @Test
    func theAlertFollowsIntelliJsTrustDialog() {
        let alert = WorkspaceTrust.makeAlert(for: url("/projects/My App"))

        #expect(alert.messageText == "Trust and Open Project \u{2018}My App\u{2019}?")
        #expect(alert.informativeText.contains("potentially malicious code"))
        #expect(alert.informativeText.contains("Safe Mode"))
        #expect(alert.buttons.map(\.title) == ["Trust Project", "Don't Trust"])
        #expect(alert.alertStyle == .warning)
    }

    @Test
    func theAlertResultIsTheFirstButton() {
        var shown: [NSAlert] = []
        let trusted = WorkspaceTrust.presentAlert(for: url("/projects/app")) { alert in
            shown.append(alert)
            return .alertFirstButtonReturn
        }
        let declined = WorkspaceTrust.presentAlert(for: url("/projects/app")) { _ in .alertSecondButtonReturn }

        #expect(trusted)
        #expect(!declined)
        #expect(shown.count == 1)
    }

    @Test
    func headlessModeSuppressesTheDefaultAlert() async throws {
        guard DreamderHeadless.isEnabled else { return }
        #expect(WorkspaceTrust.askUser(about: url("/projects/app")) == false)
        try await withIsolatedDefaults { defaults in
            let trust = WorkspaceTrust(defaults: defaults)
            #expect(await trust.requestTrust(for: url("/projects/app")) == false)
            #expect(trust.trustedRoots.isEmpty)
        }
    }

    @Test
    func nonHeadlessPresentationReachesTheSystemAndIsSuppressedByTheHostSwizzle() throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.runModal"))
        let alert = WorkspaceTrust.makeAlert(for: url("/projects/\(UUID().uuidString)"))

        #expect(WorkspaceTrust.runAlert(alert, headless: true) == .abort)
        #expect(!DreamderHeadless.suppressedModals.contains(alert.messageText))
        #expect(WorkspaceTrust.runAlert(alert, headless: false) == .abort)
        #expect(DreamderHeadless.suppressedModals.contains(alert.messageText))
    }
}
