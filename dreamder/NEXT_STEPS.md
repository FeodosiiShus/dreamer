# Next steps

Status when work stopped (2026-11-09). Read `AGENTS.md` first; this file lists only what is still open.

## Last verified state

- `make build` (Swift and C warnings are errors in the project targets), `make check`, `make lint` and `make smoke` pass.
- `make coverage COVERAGE_CHECK=1`, run 15: 9 704 tests passed, coverage 100.00 % (106 492 of 106 492 lines, every file 100 %), gate passed. The confirmation run right after it had 2 load-dependent failures (`DiagnosticTooltipPresenterTests/monitorForwardsMouseMovesAndDismissesOnInput`: the hover never scheduled its sleeper; `CommitToolWindowCoverageTests/aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit`: `changedFiles` not empty) and, as a consequence, small gaps in `DiagnosticHighlightTooltip.swift`, `RegistryItemTemplateParser.swift` and `WorkspaceFileScope.swift`.
- Terminal show/hide on the main thread: about 35–50 ms per toggle (Time Profiler, 12 toggles), down from 80–120 ms; `Buffer.resize` no longer appears in the profile.

## To do

1. Make the two tests above deterministic, then confirm two consecutive `make coverage COVERAGE_CHECK=1` runs with 0 failures and 0 host restarts, and run `make coverage-baseline` right after a green run (never while another `make coverage` deletes the bundle).
2. Watch CI on macOS 26 (Xcode 26.6) and Xcode 27.2. The SPM cache key changed to `spm-v2-…` so the runners fetch an unstubbed SwiftLint binary for `make lint`.
3. Flaky under load, root cause not found:
   - Task output that never reaches the terminal (`CEActiveTaskTests/testRunMethod(.zsh)`): suspected pty race when a fast child exits before SwiftTerm's `LocalProcess` reads. Tests that need the output now assert a file side effect instead.
   - `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent` (now waits with `eventually`).
4. Descriptor hygiene: `forkpty` children (SwiftTerm `LocalProcess`) inherit every non-close-on-exec descriptor of the app, and `LocalProcess` never closes the pty master. Both need a package fork or upstream fix.
5. SwiftLint debt: `Scripts/swiftlint-baseline.json` records the pre-existing violations; `make lint` fails only on new ones. Pay it down file by file and regenerate with `make lint-baseline`.
6. Known product follow-ups:
   - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields.
   - vtsls ignores the `tsserver.path` initialization option, so an untrusted workspace can still make vtsls load the project's TypeScript; Pyright's own virtual-environment detection is not trust-gated either.
   - A language server already running when a workspace becomes trusted keeps its untrusted options until it restarts (the Safe Mode notification's action restarts it).
