# Research of 2026-11-09

Three research streams and one audit, all read-only except where this file says a change was made. Every external claim in the detail files cites the official documentation of the tool it describes; `[INFERENCE]` marks what was derived and not observed.

| File | Contents |
|---|---|
| `ci-runners.md` | GitHub-hosted macOS runner labels and hardware, job concurrency and queue limits, artifact and cache rules, action versions, comparison of CI topologies. |
| `xcode-test-speed.md` | `xcodebuild` test actions and identifiers, parallel-testing switches, Swift Testing parallelism, build-speed settings, coverage tooling, ranked recommendations. |
| `swift-standards-checklist.md` | 40 production-readiness rules for a Swift 6 macOS editor, each with a detection pattern and an official citation, ordered by risk reduction. |
| `bugs-*.md` | Six audit reports, one per area of `Dreamder/`: failing sequence, evidence, standard, fix sketch and reproducing test for every finding. |
| `test-shared-state.md` | Audit of process-wide state that tests mutate while other suites run in the same host: ranked hazards with their production readers, and the three isolations that remove most of the risk. |

## Why CI was red and slow

Run 42691211270 (commit `827e7804bf`):

- The macOS 26 job never started: `The job was not acquired by Runner of type hosted even after multiple attempts`. GitHub documents neither the message nor a setting that prevents it; re-running the failed job is the documented answer (`ci-runners.md`, Q2).
- The macOS 27 job compiled the app twice before the first test ran: `make build` without instrumentation (8 min 5 s), then `make coverage` with instrumentation (7 min 39 s). `make smoke` would have compiled it a third time and `make release` a fourth.
- The unit tests took 19 min 25 s and failed on `CEActiveTaskCoverageTests/interruptSendsSigintToARunningTask(.bash)`: `Time limit was exceeded: 120.000 seconds`, followed by a host restart. `bugs-process-terminal.md`, section 1, shows it is a test defect: three chained waits of up to 90 s each, a signal loop that ends by itself with exit code 0, and a marker read from terminal text. The test now uses bounded waits, a marker file and `exit 7` for an unhandled signal; `make test FLAVOR=coverage FILTER=CEActiveTaskCoverageTests` passes.

Runs of the new workflows on 2026-11-10 (one instrumented build per platform, products handed to the test, coverage and smoke jobs):

| Run, commit | macOS 26 / Xcode 26.6 | macOS 27 / Xcode 27.2 | What it showed |
|---|---|---|---|
| 42706519487, `7886dab2c6d5` | build and Release failed after 5 min | build 17 min, smoke passed, one test shard failed after 1 812 s | `FinderSync.swift` did not compile under Swift 6.3; twelve tests hit the 120 s allowance while queued behind the UI gate |
| 42721773641, `9f6f32d62ea1` | build and Release failed after 9 and 18 min | build 13 min, smoke passed, two shards ran 5 158 tests in 457 s and 5 073 in 713 s with one failure each | Swift 6.3.3 crashes in IR generation on a `Binding` setter passed as a method reference; a test read terminal text, another had its document autosaved by the process-wide flag |
| 42725881580, `2b0049799117` | Release passed (18 min 41 s); the build compiled the app and listed the remaining errors | build and smoke passed, shard 1 passed, shard 0 failed on one test | four UI-test files lacked `@MainActor` for the macOS 26.5 SDK, one test sent a `CodeFileDocument` through `Task.value`; a Markdown test depended on a single `Task.yield()` |

## Where the local test time went

Machine: M1 Pro, 10 cores, Xcode 27.2. The suite has 9 822 test cases (9 704 tests) in 975 suites.

| Run | Unit-test phase | Result |
|---|---|---|
| One host, before | 802 s (825 s with host start-up) | passed, coverage 100 % |
| One host, after the defaults-key fix, new Makefile and fresh instrumented build | 757 s | 9 704 tests passed; gate short by 2 lines (`FileEventBatcher.swift` 69/70, `SequenceDiff.swift` 431/432) |
| One host, after the fix, host restarted after 4 minutes by CRASH-1 | 471 s | failed on the crash; the second host ran the last 2 925 tests in 213 s |
| Three hosts, after the fix (`Scripts/sharded-tests.py --flavor coverage --shards 3`, the body of `make coverage-sharded`) | 245 s (shards 215 s, 227 s, 224 s) | 2 failures in one shard, merged coverage 99.92 % |
| Three hosts, after the bug-fix wave of 2026-11-10 (third full run) | 249 s (shards 236 s, 233 s, 230 s) | 10 197 passed, none failed, gate passed at 100 %; shard 0 was restarted once by CRASH-1 |
| One host, after the bug-fix wave (`make coverage FLAVOR=coverage COVERAGE_CHECK=1`) | 803 s | 10 231 tests in 1 047 suites passed, no restart, gate passed: 82 372 of 82 372 executable lines |

| Build step, as the CI build job runs it | Time |
|---|---|
| `make build-for-testing FLAVOR=coverage` into an empty `.build/xcode-coverage` (packages cloned from the local SwiftPM cache, app and tests instrumented) | 230 s |
| `make lint FLAVOR=coverage` right after it | 2 s |
| `make pack-test-products FLAVOR=coverage` | 1 s, archive of 135 MB |
| Clean instrumented `build-for-testing` of an export of `2b0049799117` with `COMPILATION_CACHE_ENABLE_CACHING=YES`, empty cache | 229 s, `CompilationCache.noindex` 1.9 GB |
| The same build again after deleting `Build/` and keeping the cache | 32 s |

- 120 main-thread stall samples of the test host (`.build/logs/stalls`, threshold 3 s): in 54 the main thread was inside `removeDefaultsKeys`/`removeStandardDefaultsKeys`, the cleanup that every `withTempDir` runs. The process was 93 % idle in those samples. The hot frames were `_StringGuts._opaqueCharacterStride`, `_CFStringGetCStringPtrInternal` and grapheme breaking: `String.contains` over keys bridged from `UserDefaults`. The helper now searches through `NSString.range(of:options:)` (`DreamderTests/Utils/withTempDir.swift`).
- A long-lived host slows down as it runs: the key-match fix alone saved 6 % (802 s to 757 s), a restart in the middle saved 38 %, three fresh hosts took a third of the time. What accumulates in the host is not identified; two of the eleven CI stall samples end in `_CFXNotificationRegistrarRemoveObservers` under a `deinit`. Every test host on the machine also shares one preferences domain with the installed app.
- `CFFIXED_USER_HOME` passed through `TEST_RUNNER_` does not move the preferences domain of the test host: the real `dev.dreamder.Dreamder` plist kept changing and the substitute home stayed empty.
- Three hosts are a gate since 2026-11-10. The two failing tests were fixed. The files below 100 % were an artifact of the merged bundle's function-level report, not missing coverage: `xcresulttool merge` lists some functions a second time with zero coverage (`SemanticTokenMap.decode(tokens:using:)` read 0/19 in the merged report and 19/19 in two of the three shards; the file had 87 executable lines in the merged report and 68 in every shard), while the line data of the merged archive (`xccov view --archive --json`) was identical to the union of the three shards for all 900 files. `Scripts/coverage-report.py` now counts distinct executable lines from the archive and names the uncovered lines.

## CRASH-1 (P0): highlighter state mutated off the main thread

Evidence: `~/Library/Logs/DiagnosticReports/Dreamder-2026-11-09-231614.ips`, test host, `EXC_BAD_ACCESS (SIGSEGV)`, thread `com.apple.root.user-initiated-qos.cooperative`:

```
_swift_release_dealloc
SetAlgebra.subtract(_:)
HighlightProviderState.invalidate(_:)                              HighlightProviderState.swift:116
closure #1 in HighlightProviderState.storageDidUpdate(range:delta:) HighlightProviderState.swift:145
closure #3 in TreeSitterClient.applyEdit(textView:range:delta:completion:) TreeSitterClient.swift:180
closure #1 in TreeSitterExecutor.execAsync(priority:operation:onCancel:)   TreeSitterExecutor.swift:115
```

Cause, in the CodeEditSourceEditor package: `TreeSitterClient.applyEdit` hops to the main queue on its synchronous path (`TreeSitterClient.swift:171`, `DispatchQueue.dispatchMainIfNot`) and on cancellation (`:185`), but the asynchronous path calls the completion directly inside the executor task (`:180`, `operation: { completion(.success(operation())) }`). The completion mutates `validSet` of `HighlightProviderState`, a `@MainActor` class, while the main thread uses it. The asynchronous path is taken for long edits and long documents (`Constants.maxSyncEditLength`, `Constants.maxSyncContentLength`) and also whenever `TreeSitterExecutor.execSync` refuses because another task is queued (`TreeSitterExecutor.swift:80`), for example an edit while the initial parse of `setUp` is still running. The race is therefore reachable in any file, and it restarted a test host again on 2026-11-10 (`Dreamder-2026-11-10-010700.ips`, same frames).

Fix, 2026-11-10: the project is pinned to a fork, `https://github.com/FeodosiiShus/CodeEditSourceEditor` at revision `488079a386ec299c86d7787a0a65e884dd7a4347` (branch `dreamder/0.15.1`, upstream 0.15.1 plus one commit), where the asynchronous path reads `let invalidatedRanges = operation()` and then `DispatchQueue.dispatchMainIfNot { completion(.success(invalidatedRanges)) }`. `TreeSitterClientEditCompletionTests` pins it with a long edit that must take the asynchronous path. An app-side `HighlightProviding` decorator was not possible: `TextViewController.init` takes its `treeSitterClient` (tag completion, jump to definition) from the first concrete `TreeSitterClient` among the providers (`TextViewController.swift:227-229`), the class is `final`, the property is `internal(set)`, and any `TreeSitterClient` left in the provider list is driven by the highlighter directly. The package's `main` branch still has the defect, so the fork stays until upstream fixes it.

Standard: data-race safety and main-actor isolation; the rules and their official citations are the data-race entries of `swift-standards-checklist.md`.

## Bug audit: all findings

12 P0, 22 P1 and 27 P2 findings. Status on 2026-11-10: every finding in the table is fixed with regression tests, see "Fix status" at the end of this file; the reports keep the original analysis and name the reproducing test. Confidence and unverified assumptions are stated per finding in the reports.

| Id | Severity | Defect | Report |
|---|---|---|---|
| CRASH-1 | P0 | Highlighter state is mutated off the main thread after an asynchronous tree-sitter edit; the process dies with `EXC_BAD_ACCESS` | this file |
| B-01 | P0 | Stale undo stack after a tab is closed | `bugs-editor-documents.md` |
| B-02 | P0 | Save actions bypass the undo manager when no text view is attached | `bugs-editor-documents.md` |
| LSP-01 | P0 | Untrusted workspaces still start servers that execute workspace code | `bugs-lsp.md` |
| F1 | P0 | Task runs in the app's working directory when its own directory is missing | `bugs-process-terminal.md` |
| BUG-01 | P0 | One malformed key resets all settings; next change overwrites the file | `bugs-settings-markdown.md` |
| BUG-02 | P0 | Unauthenticated automation hooks in every build, with a persistable gate | `bugs-settings-markdown.md` |
| SC-01 | P0 | Chip click after a manual edit discards the hand-written result | `bugs-source-control.md` |
| SC-02 | P0 | Merge tool corrupts non-UTF-8 files | `bugs-source-control.md` |
| SC-03 | P0 | Shelve/unshelve throw away unsaved editor edits, even on failure | `bugs-source-control.md` |
| SC-04 | P0 | Ref names reach git as bare positionals | `bugs-source-control.md` |
| WUI-1 | P0 | Replace on drop or cut-paste permanently deletes the folder that contains the dragged item | `bugs-workspace-ui.md` |
| B-03 | P1 | Shared `CodeFileTextViewBinder` detaches the text view that is still on screen | `bugs-editor-documents.md` |
| B-04 | P1 | FSEvents rescan and dropped-event flags are thrown away | `bugs-editor-documents.md` |
| B-05 | P1 | Save actions produce one undo step per trimmed line | `bugs-editor-documents.md` |
| B-06 | P1 | Renaming a file to the same name in a different case is refused | `bugs-editor-documents.md` |
| B-07 | P1 | `.editorconfig` values stay those of the old path after a rename | `bugs-editor-documents.md` |
| LSP-02 | P1 | `closeWorkspace` never matches workspaces whose path needs percent-encoding | `bugs-lsp.md` |
| LSP-03 | P1 | Pending edits are sent twice after a server is reopened | `bugs-lsp.md` |
| LSP-04 | P1 | Workspace edits ignore the document version and unflushed edits | `bugs-lsp.md` |
| LSP-05 | P1 | Open documents lose their server when another start wins the restart race | `bugs-lsp.md` |
| LSP-06 | P1 | A document closed during backoff or restart is reopened and never closed | `bugs-lsp.md` |
| F2 | P1 | Unsupported login shell leaves the task `.running` forever with no process | `bugs-process-terminal.md` |
| F3 | P1 | Stop (SIGTERM) on a bash task kills the current command and bash runs the next one | `bugs-process-terminal.md` |
| F4 | P1 | Raw `waitpid` status is decoded as an exit code | `bugs-process-terminal.md` |
| F5 | P1 | Every signal is delivered twice to the root and its group | `bugs-process-terminal.md` |
| F6 | P1 | Failed `execve` leaves a forked copy of the app running | `bugs-process-terminal.md` |
| BUG-03 | P1 | Raw HTML `id="dreamderPreview"` permanently disables preview updates | `bugs-settings-markdown.md` |
| BUG-04 | P1 | `URL.lspURI` is not percent-encoded | `bugs-settings-markdown.md` |
| SC-05 | P1 | Applying a merge result converts CRLF and CR to LF | `bugs-source-control.md` |
| SC-06 | P1 | Rollback of a renamed file leaves it deleted | `bugs-source-control.md` |
| SC-07 | P1 | Any branch whose name contains "HEAD" is hidden | `bugs-source-control.md` |
| SC-08 | P1 | Partial-commit patch is built from raw worktree bytes | `bugs-source-control.md` |
| WUI-2 | P1 | Quit with unsaved documents never interrupts running tasks | `bugs-workspace-ui.md` |
| B-08 | P2 | A case-only rename leaves both names in the file scope | `bugs-editor-documents.md` |
| B-09 | P2 | Pointer returned out of `withUnsafeMutablePointer` | `bugs-editor-documents.md` |
| B-10 | P2 | Opening and reloading read and decode the whole file on the main actor | `bugs-editor-documents.md` |
| B-11 | P2 | Duplicate removes every occurrence of the extension from the base name | `bugs-editor-documents.md` |
| LSP-07 | P2 | Edits for editor-open documents the client does not track go straight to disk | `bugs-lsp.md` |
| LSP-08 | P2 | Edits typed while the first `didOpen` is in flight are dropped | `bugs-lsp.md` |
| LSP-09 | P2 | Position conversion does not clamp `character` to the line | `bugs-lsp.md` |
| LSP-10 | P2 | Server file operations run unconfined and delete permanently | `bugs-lsp.md` |
| LSP-11 | P2 | `documentOperations` grows for every URI ever opened | `bugs-lsp.md` |
| F7 | P2 | `LocalProcessPump.pending` is unbounded | `bugs-process-terminal.md` |
| F8 | P2 | `ProcessSlotPool.acquire` can lose a cancellation | `bugs-process-terminal.md` |
| F9 | P2 | Concurrent `runTask` calls for one task are not serialized | `bugs-process-terminal.md` |
| F10 | P2 | Task shells inherit the app's signal mask and ignored dispositions | `bugs-process-terminal.md` |
| F11 | P2 | `ProcessTree.send` signals a snapshot | `bugs-process-terminal.md` |
| F12 | P2 | Make targets are interpolated into a shell command unquoted | `bugs-process-terminal.md` |
| BUG-05 | P2 | `MarkdownListEnter` traps with the caret between CR and LF | `bugs-settings-markdown.md` |
| BUG-06 | P2 | Raw HTML may carry `md-src-pos` and pin scroll sync | `bugs-settings-markdown.md` |
| BUG-07 | P2 | `escapedDirectory()` is not a safe shell quoting | `bugs-settings-markdown.md` |
| SC-09 | P2 | Partial staging resets the index before the patch is known to apply | `bugs-source-control.md` |
| SC-10 | P2 | An excluded hunk is silently re-included once its content changes | `bugs-source-control.md` |
| SC-11 | P2 | Renaming a shelf drops the stash before re-storing it | `bugs-source-control.md` |
| SC-12 | P2 | A failed `git status` is shown as a clean tree and "All conflicts have been resolved" | `bugs-source-control.md` |
| WUI-3 | P2 | Replace in Files rewrites files in place (truncate, then write) | `bugs-workspace-ui.md` |
| WUI-4 | P2 | Per-workspace UserDefaults keys are never removed | `bugs-workspace-ui.md` |
| WUI-5 | P2 | Project filter walks the whole tree synchronously on the main actor | `bugs-workspace-ui.md` |
| WUI-6 | P2 | Symbol index applies every file-system delta in O(all symbols) on the main actor | `bugs-workspace-ui.md` |
| WUI-7 | P2 | Search Everywhere text search keeps running after the panel is gone | `bugs-workspace-ui.md` |

## Fix status (2026-11-10)

All 61 findings are fixed. Sixty are fixed in the application, each with regression tests written from the failing sequence in its report (the tests were run on the fixed code only, not against the old code); CRASH-1 is fixed in a fork of the `CodeEditSourceEditor` package (section above).

| Area | Findings | Where the fix lives |
|---|---|---|
| Processes, terminal, tasks | F1 to F12, BUG-07 | `Features/TerminalEmulator/Model/` (`ProcessExit`, `ShellLaunch`, `SignalMask`, `ProcessTree`), `Features/Tasks/` (`TaskManager+Shutdown`, `TaskEscalations`, stop requests end as cancelled), `Utils/Process/ProcessSlotPool.swift`, `String.shellQuoted()` |
| Language servers | LSP-01 to LSP-11, BUG-04 | `LSP/Discovery/UntrustedWorkspaceServerPolicy.swift`, `LSP/Service/LSPWorkspaceEditExecutor.swift` and `WorkspaceEditApplier` (version check and apply in one main-actor section, edits confined to the workspace, deletes go to the Trash), percent-encoded and canonically decomposed `URL.lspURI`, per-URI operation queue for close and reopen |
| Source control | SC-01 to SC-12 | `SourceControl/MergeTool/` (`LineEnding`, `ThreeWayMerge+Text`, non-UTF-8 files refused), `SourceControlManager.changedFilesFailure`, `--end-of-options` and ref-name validation in `Client/`, shelf and commit tool window flows |
| Editor and documents | B-01 to B-11 | `CodeFileDocument` (undo registration, one undo group per save, asynchronous load above `FileSizeLimit.synchronousOpen`), `CodeFileTextViewBinder` (weak controller list), `DiskWorkspaceFileSystem`, FSEvents flags, case-only renames |
| Workspace UI | WUI-1 to WUI-7 | `ProjectNavigatorItemReplacement` (replace keeps a backup until the move succeeds), `ProjectNavigatorFilterMatches` (filter walks off the main actor), `AppDelegate+Termination` (quit stops tasks first), atomic Replace in Files, Search Everywhere task lifetime |
| Settings, automation, Markdown | BUG-01 to BUG-06 | `Settings/Models/LenientDecoding.swift` (a bad key keeps the rest, an unreadable file is preserved), `DreamderHeadless+Resolution.swift`, sanitizer namespace for raw HTML ids and `md-src-pos`, `MarkdownTextLines+InsertionPoint.swift` |

B-10 is bounded, not removed: files up to `FileSizeLimit.synchronousOpen` (1 MiB) still load on the main actor so `openTab` stays synchronous, larger files load asynchronously into a document in loading state.

One more defect surfaced while a flaky test was traced, and is fixed the same way: the git gutter lost a HEAD change that kept the branch name and the changed-file list (a commit, fast-forward or reset on a clean tree), because `GitGutterCoordinator.RepositorySignature` had no commit identity and a `refs/heads` event only refreshed the branch list. The signature now carries `SourceControlManager.currentHeadCommit` and the event also refreshes the current branch (`GitGutterStalenessTests/fastForwardOnTheSameBranchWithCleanTreeReloadsHead`).

## Task output lost when the shell exits before the app has read it (2026-11-14)

Symptom, seen in three sessions as "flaky under load, root cause not found": a task that prints and exits at once (`echo confirmed-$((1+1))`) ends as `Finished` with exit status 0, and its output never reaches the terminal. Tests that read terminal text failed about once in two or three full runs (`CEActiveTaskTests/testRunMethod(.zsh)`, `ActiveTaskTerminalLaunchTests/anUnsupportedLoginShellFallsBackToZshAndTheTaskStillRuns`, `TaskManagerTrustTests/aConfirmedWorkspaceRunsAndIsNotAskedAgain`), always tests whose shell exits right after printing, never tests whose shell keeps running.

Cause, measured with a C program that calls `forkpty`, runs `zsh -lic 'echo marker-$((40+2))'` and reads the primary side of the pseudo-terminal only after a delay (macOS 27.2, Not documented in official sources):

| Parent holds its own descriptor of the secondary side | Read starts | Result |
|---|---|---|
| no | 0.05 s after the start | 11 bytes, then end of file |
| no | 1.5 s after the start | 0 bytes, end of file, exit status 0; the exit event (`EVFILT_PROC`, `NOTE_EXIT`) arrived after 0.64 s without any read |
| no, shell killed with `SIGKILL` while it sleeps after printing | 1.5 s | 0 bytes |
| yes | 1.5 s and 6 s | 11 bytes, then end of file; the exit event arrived only after the read, 40 runs of 40 |
| yes, shell killed with `SIGKILL` or `SIGHUP` | 1.5 s | 11 bytes, exit status is the signal |
| yes, 20 kB of output | 1.5 s | 20 011 bytes |

When the shell is the only process that has the secondary side open, its exit waits about half a second for the reader and then discards what was not read. SwiftTerm's `LocalProcess` reads through `DispatchIO` on a queue without a quality-of-service class, so under load (three test hosts, a three-core CI runner, or a busy machine) the first read can be later than that. With a prompt reader nothing is lost: 8 000 sessions of the same command through the same `DispatchIO` code lost none.

Fix: `CELocalShellTerminalView.spawn` opens the secondary side in the app (`PtySecondaryHold`, `O_RDWR | O_NOCTTY | O_CLOEXEC`) and releases it when the exit is delivered. The kernel then keeps the exiting shell until the app has read everything and reports the exit afterwards. `PtySecondaryHoldTests` runs the measurement above as tests (late reader, killed shell).

Two more defects found on the way, both fixed:

- SwiftTerm calls `waitpid(pid, &status, WNOHANG)` once when the exit event fires and reports status 0 when the child is not reapable yet. That happened in 12 of 8 000 sessions; such a task shows as finished whatever its real status, and the zombie stays. `LocalProcessPump.resolveTermination` asks again (`ChildReap.nonBlocking`, at most 250 times, 2 ms apart, on the pump queue) and reports the real status.
- zsh integration scripts live in one directory per user, shared by every session of every Dreamder process, and each start removed and copied all four. A shell starting in between found a script missing, and two starts at once made `setUpIntegration` throw: 86 failures in 240 task starts while a second process reinstalled the scripts in a loop. A terminal tab does not start at all in that case ("Failed to start a terminal session"). `ShellIntegration.installScript` writes atomically and only when the content differs.

Not fixed, needs a SwiftTerm change: `LocalProcess` never closes the primary descriptor, and macOS allows 511 pseudo-terminals for the whole system (`sysctl kern.tty.ptmx_max`). A stress program that kept its descriptors the same way got `forkpty` error `ENXIO` after 510 sessions.
