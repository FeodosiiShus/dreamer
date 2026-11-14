# Next steps

Status when work stopped (2026-11-14, night session). Read `AGENTS.md` first; this file lists only what is still open. Research, measurements, the bug audit and its fix status are in `docs/research/README.md`.

## Last verified state

- The third batch (Swift 6.3.3 fixes for the test targets, strict coverage gate, test isolation, compilation caching) and the fixes of 2026-11-14 are commit `95aac6378eb6` on top of `2b0049799117`; the commit after it holds what its CI run found.
- Local gate on Xcode 27.2 right before that commit: `make check`, `make lint`, `make coverage-sharded COVERAGE_CHECK=1` (three shards passed, strict gate at 100 %), `make smoke` on the instrumented build, `make release`.
- Fixed on 2026-11-14, each with tests:
  - Task output lost when the shell exits before the app has read it: the root cause of the tests that were "flaky under load" (`docs/research/README.md`, last section). The terminal view holds the secondary side of the pseudo-terminal while a shell runs (`PtySecondaryHold`).
  - Exit status 0 reported for a child that SwiftTerm could not reap yet (`ChildReap`, `LocalProcessPump.resolveTermination`).
  - zsh integration scripts removed and copied on every start in a directory all sessions share (`ShellIntegration.installScript`).
  - Gutter line numbers painted outside the editor pane, over the breadcrumbs bar and over the split below (`EditorBackgroundCoordinator`).
  - `EventModifiers.hidden` was a `static var`, which Swift 6.3.3 rejected from the test target (CI run 42725881580).
  - Three coverage gaps the isolation seams of the third batch had opened (`DreamderDocumentController.openDocument(panels:)`, `WelcomeServices.applicationWindows`, the `Settings` subscript setter).
- Not verified locally: Swift 6.3.3 and macOS 26. Only Xcode 27.2 is installed, so CI is the only check; the test shards and the coverage job have never run on macOS 26.
- CI run 43540188691 on `95aac6378eb6`: Release app passed; on macOS 27 the build, smoke and both test shards passed for the first time and the coverage gate ran for the first time. It found two gaps the local gate cannot see: `CodeFileView.editorTheme(for:)` reads the background image path from the standard defaults, which are set on the developer machine and empty on the runner, and the setter of `WelcomeProjectsList.queryBinding` ran locally only through key events that need the key window. Both now have tests that do not depend on the machine (`CodeFileViewBackgroundImageTests` with `.defaultAppStorage`, the binding set directly). The macOS 26 build listed three more Swift 6.3.3 errors, fixed in the next commit: nested enums of `DreamderUITests/Query.swift` without `@MainActor`, a document returned from an `#expect(throws:)` closure, a document captured by `Task.detached`.
- CI before that, run 42725881580 on `2b0049799117`: Release app passed; macOS 27 build, smoke and shard 1 passed, shard 0 failed on one Markdown test that is now replaced; the macOS 26 build listed the Swift 6.3.3 errors of the test targets that this commit fixes.
- Test isolation (`docs/research/test-shared-state.md`): rows 1 to 6 and 8 of the audit are done. Inside a test host no document autosaves on a timer unless the test opts in.
- Compilation caching is on for every command-line build and cached on CI per runner and week; it has never run on CI. Locally a clean rebuild with a warm cache took 32 s against 229 s.

## To do

1. Watch CI until both platforms and the Release job are green. Expect iterations on macOS 26: its test shards and coverage job have never run, and a line that only one macOS version executes fails the absolute gate on the other.
2. Close the primary descriptor of a finished terminal session. Every session keeps one of the 511 pseudo-terminals macOS allows system-wide until the app quits; a local run of three shards held 360 at its peak (two CI shards hold about half of that each). SwiftTerm's `LocalProcess` owns the `DispatchIO` channel and gives no access to it. A way without a fork that was not tried: open a second `DispatchIO` channel on the same descriptor whose cleanup handler closes it, replace the view's `LocalProcess` once the exit is delivered so SwiftTerm's channel is released, and close the second channel; libdispatch runs the cleanup handlers only after every channel on the descriptor is gone.
3. Check on the second CI run with a warm compilation cache how long the build jobs take and how large the `cas-v1-*` caches are (GitHub keeps 10 GB per repository); drop the cache steps if they do not pay.
4. Send the one-commit fix of the fork upstream (`CodeEditApp/CodeEditSourceEditor`, `TreeSitterClient.swift:180`) and return to the upstream package once it is released.
5. Remaining rows of `docs/research/test-shared-state.md` (7 and 9 to 16): `LSPService.shared.languageClients` registrations in tests, `NotificationManager.shared`, the shift monitor and Escape event monitors, `CommandManager.shared` ids, `NSApp.appearance`, standard-defaults keys. One more shared thing showed up on 2026-11-14: the application's key window. Fifteen test files send key events through `NSApp.sendEvent`, which delivers them to whatever window is key; `BranchesPopupKeyMonitorCoverageTests/monitorStaysQuietWhileAMenuIsTracked` counted four key events of another suite (fixed by counting only events addressed to its own window). The other files have not been audited for the same assumption.
6. Give each test host its own preferences domain. Every host on the machine shares `dev.dreamder.Dreamder` with the installed app, tests leave keys in it, and `CFFIXED_USER_HOME` does not redirect it.
7. An arm64-only Release build is still worth measuring (`docs/research/xcode-test-speed.md`); it changes the shipped artifact.
8. Dead code found during the fixes, left in place: `String.fullCommand`, `escapedQuotes`, `escapedWhiteSpaces`, `escape(replacing:)`, `MergeToolPresenter.showConflictsForActiveWorkspace(resolve:)` and the setter of the static `Settings` subscript have no production callers.
9. Flaky under load, root cause not found: `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent`, `DiagnosticTooltipPresenterTests/monitorForwardsMouseMovesAndDismissesOnInput` and `CommitToolWindowCoverageTests/aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit` (seen in earlier sessions, not in the last runs).
10. Descriptor hygiene: `forkpty` children (SwiftTerm `LocalProcess`) inherit every non-close-on-exec descriptor of the app, and SwiftTerm runs Swift code between `fork` and `execve`. Both need a package fork or upstream fix.
11. SwiftLint debt: `Scripts/swiftlint-baseline.json` records the pre-existing violations; `make lint` fails only on new ones. Pay it down file by file and regenerate with `make lint-baseline`.
12. Known product follow-ups:
    - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields.
    - Files up to 1 MiB (`FileSizeLimit.synchronousOpen`) are still read and decoded on the main actor when a tab opens (B-10 is bounded, not removed).
    - In an untrusted workspace only typescript-language-server starts; there is no per-server opt-in short of trusting the project.
