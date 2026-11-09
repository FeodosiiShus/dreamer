# Next steps

Status when work stopped (2026-11-10, night session). Read `AGENTS.md` first; this file lists only what is still open. Research, measurements, the bug audit and its fix status are in `docs/research/README.md`.

## Last verified state

- Bug audit: 60 of 61 findings are fixed with regression tests (`docs/research/README.md`, "Fix status"). CRASH-1 is open.
- Local, Xcode 27.2, working tree on top of `7886dab2c6d5`: `make check` clean; `make lint` clean (baseline went from 3 556 to 3 528 entries, the six rewritten entries are size debts that shrank); `make build-for-testing FLAVOR=coverage` green.
- One host, the canonical gate (`make coverage FLAVOR=coverage COVERAGE_CHECK=1`): `Test run with 10231 tests in 1047 suites passed after 803.038 seconds`, 117 XCTest tests with 0 failures, no host restart, `Coverage check passed: total 100.00%, logic 100.00%` (82 372 of 82 372 executable lines, 900 files). `Scripts/coverage-baseline.json` is rewritten from this run.
- Three hosts (`Scripts/sharded-tests.py --flavor coverage --shards 3`), run just before it: 10 197 passed tests, none failed, 249 s wall, same gate result on the merged bundle. Shard 0 was restarted once by CRASH-1 (`~/Library/Logs/DiagnosticReports/Dreamder-2026-11-10-010700.ips`: `closure #3 in TreeSitterClient.applyEdit` → `HighlightProviderState.getNextRange` on a cooperative thread), so the shard exit code was a failure although every test passed.
- CI run 42706519487 on `7886dab2c6d5` failed for two reasons, both fixed in the working tree and not yet seen by GitHub:
  1. macOS 26 / Xcode 26.6 build and Release job: `OpenWithDreamder/FinderSync.swift:39:17: capture of 'finderSync' with non-Sendable type 'FIFinderSyncController' in a '@Sendable' closure` (Swift 6.3). The build stopped there after five minutes, so the Swift 6.3 compiler has not compiled the app or the tests yet.
  2. macOS 27 / Xcode 27.2 tests: one shard took 1 812 s and twelve tests hit `Time limit was exceeded: 120.000 seconds` while they waited for the UI gate. The workflow now runs two shards per platform with `TIME_ALLOWANCE=600`.
- On that run the new topology worked on `xcode-27`: instrumented build 17 min, `archive: false` handoff of `test-products-xcode-27.tar.zst` (138 MB), headless smoke on the downloaded products 1 min 30 s.

## To do

1. Commit and push the working tree, then watch the run. Expect iterations: Swift 6.3 has not compiled the new code, the coverage merge job has never run on GitHub, and lines that only one macOS version executes would fail the absolute gate on the other.
2. CRASH-1: `TreeSitterClient.applyEdit` in `CodeEditSourceEditor` 0.15.1 (and on its `main` branch) calls the completion from the executor's task; the fix is `DispatchQueue.dispatchMainIfNot { completion(.success(result)) }` at `TreeSitter/TreeSitterClient.swift:180`. It needs a fork or a vendored copy of the package; the application cannot wrap the client (`docs/research/README.md`). Until then any test host or CI shard can restart at random, and the app can crash while typing during a parse.
3. After CRASH-1: two consecutive full runs with no host restart, in one host and in three.
4. Give each test host its own preferences domain. Every host on the machine shares `dev.dreamder.Dreamder` with the installed app, tests leave keys in it, and `CFFIXED_USER_HOME` does not redirect it.
5. Build settings still worth measuring (`docs/research/xcode-test-speed.md`): `COMPILATION_CACHE_ENABLE_CACHING=YES` and an arm64-only Release build. `RUN_DOCUMENTATION_COMPILER=NO` and `COMPILER_INDEX_STORE_ENABLE=NO` are applied to every command-line build.
6. Dead code found during the fixes, left in place: `String.fullCommand`, `escapedQuotes`, `escapedWhiteSpaces`, `escape(replacing:)` and `MergeToolPresenter.showConflictsForActiveWorkspace(resolve:)` have no production callers.
7. Flaky under load, root cause not found:
   - Task output that never reaches the terminal (`CEActiveTaskTests/testRunMethod(.zsh)`): suspected pty race when a fast child exits before SwiftTerm's `LocalProcess` reads. Tests that need the output assert a file side effect instead.
   - `GitGutterStalenessTests/branchSwitchesMakeHeadAndMarkersFollowTheCheckedOutBranch` failed once in three full runs (two `awaitCondition` timeouts under three hosts).
   - `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent`, `DiagnosticTooltipPresenterTests/monitorForwardsMouseMovesAndDismissesOnInput` and `CommitToolWindowCoverageTests/aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit` (seen in earlier sessions, not in the last three runs).
8. Descriptor hygiene: `forkpty` children (SwiftTerm `LocalProcess`) inherit every non-close-on-exec descriptor of the app, and `LocalProcess` never closes the pty master. Both need a package fork or upstream fix.
9. SwiftLint debt: `Scripts/swiftlint-baseline.json` records the pre-existing violations; `make lint` fails only on new ones. Pay it down file by file and regenerate with `make lint-baseline`.
10. Known product follow-ups:
    - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields.
    - Files up to 1 MiB (`FileSizeLimit.synchronousOpen`) are still read and decoded on the main actor when a tab opens (B-10 is bounded, not removed).
    - In an untrusted workspace only typescript-language-server starts; there is no per-server opt-in short of trusting the project.
