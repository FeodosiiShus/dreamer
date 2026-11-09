# Next steps

Status when work stopped (2026-11-09). Read `AGENTS.md` first; this file lists only what is still open.

## Last verified state

- Last complete single-process run (`make coverage`): 9 236 of 9 260 tests passed, app coverage 99.9 %. 19 of the 22 failures were one test-host crash, from a race in `DirectoryEventStream`. That race is fixed: the FSEvents context now holds a weak owner box (`DirectoryEventStreamOwner`).
- An interrupted later run had 6 147 tests passed and 1 failure: `SettingsCoreViewCoverageTests/settingsWindowContentConfiguresItsWindowOnAppear`. The test was rewritten afterwards to call `SettingsWindow.configureSettingsWindow(in:)` directly. That rewrite has not run yet.
- These last edits are not compiled: `SettingsCoreViewCoverageTests.swift`, `ActiveTaskTerminalViewCoverageTests.swift` (waits for the task output) and `DirectoryEventStream.swift`. `DirectoryEventStream.swift` was built in Debug and Release, but no test has run on it.
- `make check` is clean. `make build` and `make release` succeed.

## To do

1. Run `make coverage` twice. Both runs must pass with 0 failures and 0 host restarts. Then run `make coverage-baseline` and commit `Scripts/coverage-baseline.json`.
2. Run `make smoke`, and `make build` with 0 warnings. Earlier test-target warnings were fixed. A clean build may show new ones, so check `.build/logs/build.log` and `.build/logs/test.log`.
3. Watch CI (`.github/workflows/dreamder.yml`, macos-26 / Xcode 26.6 and xcode-27 / Xcode 27.2). The new code uses `weak let` (`DirectoryEventStreamOwner`), which needs Swift 6.2 or later. Confirm it compiles with Xcode 26.6.
4. Uncovered or unconfirmed lines from the last runs. Re-check them against a fresh `make coverage`:
   - `Utils/FilePanels/FilePanels.swift`. The panel factories are now injected and covered by `SystemFilePanelsTests`. Confirm the generic `run(_:on:)` shows 100 %.
   - The `xccov` file report and the line archive disagree for some files (`FindNavigatorOpener.swift`, `StructureTree.swift`, `GitLogPrintElements.swift`, `ComparisonUtil.swift`, `CodeActionRequest.swift`, `LSPJumpToDefinitionDelegate.swift`, `FindReplaceEngine.swift`). The line view shows every line executed. This is only seen in merged sharded results. Check them in a single-process run.
   - `CEWorkspace/Models/WorkspaceFileScope.swift` line 260.
   - `TextEditingSettings.populateCommands` default `{ .shared }` closure. Probably uncovered: no test executes the shared palette commands.
5. Flaky or slow tests seen under load. They are fixed in code but not re-verified:
   - `ActiveTaskTerminalViewCoverageTests/tasksFallBackToAPlainShellWhenTheIntegrationScriptsAreMissing` and `CEActiveTaskTests/outputIsCompleteWhenTheTaskFinishes`. Task output tail can be lost when the shell exits; see `LocalProcessPump` in `TerminalEmulator/Views/`. Root cause not fully confirmed.
   - `ProjectNavigatorMenuTests/multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent`. Diagnostic assertions were added and the root cause is unknown.
   - `GitRefreshErrorPropagationTests` (3 tests). They expected `.notGitRepository` but got "Failed to start … doesn't exist". Probably a victim of the earlier fd exhaustion (see below).
6. Descriptor leaks found in the test host (`errno 24` / `Bad file descriptor`):
   - Fixed: `LSPService()` started real `sourcekit-lsp` servers in the test host. The default dependencies are now `.forHost()`.
   - Fixed: closing a workspace never removed its terminals from `TerminalCache`, so shells kept running. `WorkspaceDocument.close()` now removes them, and the terminal view hangs up its shell on deinit.
   - Open: SwiftTerm `LocalProcess` never closes the pty master. Its `DispatchIO` cleanup handler is empty. Closing the descriptor ourselves crashes libdispatch with `EV_VANISHED`, so this needs a package fix (fork or upstream) that closes the descriptor in the cleanup handler.
   - Verify with a full run that the open descriptor count stays bounded. Use `lsof -p <test host pid>` near the end of the run.
7. Optional: `make test-sharded` / `make coverage-sharded` (`Scripts/sharded-tests.py`). They are useful for quick feedback only. Three hosts starve each other's process slots, and `xcresulttool merge` can drop a shard's coverage archive.
8. Known product follow-ups:
   - The LSP client advertises no `workspace.inlayHint` / `workspace.diagnostics` refresh support, because the `LanguageServerProtocol` package lacks those fields. It still handles both refreshes.
   - `TaskNotificationHandler` `deleteWithDelay` may be unused now that the indexer posts a plain `delete`. Check coverage and delete it if dead.
