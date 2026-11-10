# Next steps

Status when work stopped (2026-11-10, night session). Read `AGENTS.md` first; this file lists only what is still open. Research, measurements, the bug audit and its fix status are in `docs/research/README.md`.

## Last verified state

- Bug audit: all 61 findings are fixed with regression tests (`docs/research/README.md`, "Fix status"). CRASH-1 is fixed in a fork of `CodeEditSourceEditor` that the project pins by revision (`AGENTS.md`, "Package fork").
- Local, Xcode 27.2: `make check` clean, `make lint` clean, `make build-for-testing FLAVOR=coverage` green.
- One host, the canonical gate before the fork (`make coverage FLAVOR=coverage COVERAGE_CHECK=1`): `Test run with 10231 tests in 1047 suites passed after 803.038 seconds`, no host restart, `Coverage check passed: total 100.00%, logic 100.00%` (82 372 of 82 372 executable lines, 900 files).
- Three hosts with the fork (`Scripts/sharded-tests.py --flavor coverage --shards 3`): two consecutive full runs with every shard passed, no host restart, 246 s and 230 s wall, coverage gate passed at 100 % on the merged bundle. The run before the fork had one host restarted by CRASH-1.
- CI run 42721773641 on `9f6f32d62ea1`:
  - macOS 27 / Xcode 27.2: build 13 min, headless smoke passed, both test shards ran all 10 231 tests (5 158 in 457 s and 5 073 in 713 s, against 1 812 s with one shard) and each had one failing test, both fixed in the tests: `ActiveTaskTerminalLaunchTests/anUnsupportedLoginShellFallsBackToZshAndTheTaskStillRuns` waited 20 s for terminal text (now a marker file and the exit), and `ShelfUnsavedEditsTests/shelvingIgnoresUnsavedEditsOutsideTheSelectionAndReloadsCleanDocuments` had its untouched document autosaved after 2 s because `AutosavePreferenceTests` flips the process-wide `AutosavePreference.isEnabled` in the same host (the suite now turns autosave off for its documents through `CodeFileDocument.autosavingInPlace`).
  - macOS 26 / Xcode 26.6: the build and the Release job failed on a Swift 6.3.3 compiler crash in IR generation (`AGENTS.md` rule 8, `Binding` setters passed as method references). The three call sites are rewritten as closures; Swift 6.3.3 has not compiled the remaining 172 app files and the test target yet.

## To do

1. Watch CI until both platforms and the Release job are green. Expect more iterations on macOS 26: the tests and the coverage merge job have never run there.
2. Send the one-commit fix of the fork upstream (`CodeEditApp/CodeEditSourceEditor`, `TreeSitterClient.swift:180`) and return to the upstream package once it is released.
3. Give each test host its own preferences domain. Every host on the machine shares `dev.dreamder.Dreamder` with the installed app, tests leave keys in it, and `CFFIXED_USER_HOME` does not redirect it.
4. Build settings still worth measuring (`docs/research/xcode-test-speed.md`): `COMPILATION_CACHE_ENABLE_CACHING=YES` and an arm64-only Release build. `RUN_DOCUMENTATION_COMPILER=NO` and `COMPILER_INDEX_STORE_ENABLE=NO` are applied to every command-line build.
5. Dead code found during the fixes, left in place: `String.fullCommand`, `escapedQuotes`, `escapedWhiteSpaces`, `escape(replacing:)` and `MergeToolPresenter.showConflictsForActiveWorkspace(resolve:)` have no production callers.
6. Flaky under load, root cause not found:
   - Task output that never reaches the terminal (`CEActiveTaskTests/testRunMethod(.zsh)`): suspected pty race when a fast child exits before SwiftTerm's `LocalProcess` reads. Tests that need the output assert a file side effect instead.
   - `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent`, `DiagnosticTooltipPresenterTests/monitorForwardsMouseMovesAndDismissesOnInput` and `CommitToolWindowCoverageTests/aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit` (seen in earlier sessions, not in the last five full runs).
7. Descriptor hygiene: `forkpty` children (SwiftTerm `LocalProcess`) inherit every non-close-on-exec descriptor of the app, and `LocalProcess` never closes the pty master. Both need a package fork or upstream fix.
8. SwiftLint debt: `Scripts/swiftlint-baseline.json` records the pre-existing violations; `make lint` fails only on new ones. Pay it down file by file and regenerate with `make lint-baseline`.
9. Known product follow-ups:
   - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields.
   - Files up to 1 MiB (`FileSizeLimit.synchronousOpen`) are still read and decoded on the main actor when a tab opens (B-10 is bounded, not removed).
   - In an untrusted workspace only typescript-language-server starts; there is no per-server opt-in short of trusting the project.
