# Next steps

Status when work stopped (2026-11-09, late session). Read `AGENTS.md` first; this file lists only what is still open. Research, measurements and the bug audit are in `docs/research/README.md`.

## Last verified state

- CI is restructured but has not run on GitHub yet: `.github/workflows/dreamder.yml` calls `.github/workflows/dreamder-platform.yml` per platform (build once with instrumentation, test shard jobs, coverage gate, smoke) and builds the Release app in its own job. `actionlint` passes on both files.
- Local, with the new Makefile: `make build-for-testing FLAVOR=coverage` into an empty `.build/xcode-coverage` took 230 s, `make lint FLAVOR=coverage` passed, `make pack-test-products` wrote a 135 MB archive; `make test-shard FLAVOR=coverage SHARDS=40 SHARD=0` ran 229 tests through `-xctestrun` with coverage in the result bundle; `make test FLAVOR=coverage FILTER=CEActiveTaskCoverageTests` passes with the hardened signal tests. `.build/xcode` still holds an instrumented build from before the flavor split, so the first plain `make build` recompiles it once.
- `make coverage COVERAGE_CHECK=1` on the new layout: 9 704 tests passed in 757 s in one host (802 s before the defaults-key fix in `DreamderTests/Utils/withTempDir.swift`); the gate failed on 2 uncovered lines (`FileEventBatcher.swift` 69/70, `SequenceDiff.swift` 431/432). An earlier run of the same sources took 471 s because CRASH-1 restarted the host after four minutes. Three hosts: 245 s with 2 failures and 99.92 % merged coverage.

## To do

1. Push the branch and watch the first run of the new workflows on `macos-26` and `xcode-27`. Unverified until then: the `archive: false` artifact handoff of `test-products-<runner>.tar.zst`, `strategy.job-total` as the shard count, the coverage merge job, and the smoke job on downloaded products. Re-run a job that fails with `The job was not acquired by Runner of type hosted`.
2. CRASH-1: the highlighter state is mutated off the main thread after an asynchronous tree-sitter edit (`docs/research/README.md`). It crashes the app on large files and restarts the test host at random. Choose the app-side decorator or a package fork.
3. Confirm two consecutive `make coverage COVERAGE_CHECK=1` runs with 0 failures and 0 host restarts, then `make coverage-baseline`.
4. Make sharding a gate, locally and on CI: find why the merged three-shard bundle reads 99.92 % (nine files listed in `docs/research/README.md`), fix `DefinitionJumpDelegateTests/theDefaultDelegateResolvesTheWindowControllerOfTheEditorWindow` and `UtilityAreaViewModelCoverageTests/removingATerminalKillsTheShellAndEverythingItStarted` under three hosts, then raise the `shards` input of `dreamder-platform.yml`.
5. Give each test host its own preferences domain. Every host on the machine shares `dev.dreamder.Dreamder` with the installed app, tests leave keys in it, and `CFFIXED_USER_HOME` does not redirect it.
6. Bug audit: 12 P0, 22 P1 and 27 P2 findings in `docs/research/`, none fixed. Start with the data-loss group: `WUI-1`, `SC-01`, `SC-02`, `SC-03`, `B-01`, `B-02`, `BUG-01`.
7. Build settings worth measuring (`docs/research/xcode-test-speed.md`): `COMPILATION_CACHE_ENABLE_CACHING=YES`, `RUN_DOCUMENTATION_COMPILER=NO` and `COMPILER_INDEX_STORE_ENABLE=NO` for command-line builds, an arm64-only Release build.
8. Flaky under load, root cause not found:
   - Task output that never reaches the terminal (`CEActiveTaskTests/testRunMethod(.zsh)`): suspected pty race when a fast child exits before SwiftTerm's `LocalProcess` reads. Tests that need the output assert a file side effect instead.
   - `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent` (waits with `eventually`).
   - `DiagnosticTooltipPresenterTests/monitorForwardsMouseMovesAndDismissesOnInput` and `CommitToolWindowCoverageTests/aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit`.
9. Descriptor hygiene: `forkpty` children (SwiftTerm `LocalProcess`) inherit every non-close-on-exec descriptor of the app, and `LocalProcess` never closes the pty master. Both need a package fork or upstream fix.
10. SwiftLint debt: `Scripts/swiftlint-baseline.json` records the pre-existing violations; `make lint` fails only on new ones. Pay it down file by file and regenerate with `make lint-baseline`.
11. Known product follow-ups:
    - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields.
    - vtsls ignores the `tsserver.path` initialization option, so an untrusted workspace can still make vtsls load the project's TypeScript; Pyright's own virtual-environment detection is not trust-gated either.
    - A language server already running when a workspace becomes trusted keeps its untrusted options until it restarts (the Safe Mode notification's action restarts it).
