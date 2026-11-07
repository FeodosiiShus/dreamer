# dreamder

Native macOS code editor in Swift, forked from an MIT-licensed native editor (`LICENSE.md` keeps its notice), restyled and extended to look and work like IntelliJ IDEA's New UI (Islands Dark) and like Flint (`/Users/oleksandr/WebstormProjects/Flint`, the product reference). The bundled IntelliJ assets (expui icons, Islands themes, JetBrains Mono) come from the IntelliJ sources in this repository. CI: `.github/workflows/dreamder.yml` at the repository root runs `make check` on Ubuntu, then builds and tests on a matrix of `macos-26` with Xcode 26.6 (primary: coverage gate, Release app and dSYM artifacts) and `xcode-27` with Xcode 27.2.

## Rules

1. NEVER write comments or doc comments in new or edited code; leave existing comments alone.
2. Follow the existing patterns (`@EnvironmentObject` injection, `@AppSettings`, AppKit window controllers). Observation is mid-migration: `CodeFileDocument`, `GitLogViewModel`, and `GitConsoleLog` are `@Observable` (held with `let`/`@State`, injected with `@Environment(Type.self)`); everything else is still `ObservableObject`. Migrate a type whole or not at all; never mix `@Published` and `@Observable` in one type, and never use `@ObservedObject`/`@StateObject` on an `@Observable` class. Packages named `CodeEdit*` (`CodeEditSourceEditor`, `CodeEditTextView`, `CodeEditLanguages`, `CodeEditKit`, `CodeEditSymbols`) are third-party dependencies and keep their names.
3. Colors, metrics, and fonts of new chrome come from `Dreamder/Features/Islands/Islands.swift` (IntelliJ Islands Dark values). Icons are IntelliJ expui SVGs in `Dreamder/IntelliJIcons.xcassets`, addressed as `Image("<set>/<name>")` (for example `toolwindows/project_20`, `vcs/branch`, `general/search`); the full list is printed by `ls Dreamder/IntelliJIcons.xcassets/*/`.
4. Tool windows are identified by `ToolWindowID` and shown through `WorkspaceDocument.toolWindowManager` (`Dreamder/Features/Islands/ToolWindow.swift`).
5. Flint is GPL-3.0 and written in Rust: use it as a behavior and visual reference only, never copy its code or assets.
6. NEVER add a Swift package without user approval.
7. New files inside `Dreamder/`, `DreamderTests/`, and `DreamderUITests/` are picked up automatically (file-system synchronized groups); never hand-edit `project.pbxproj` to add files.
8. Deployment target is macOS 26.0. Locally the SDK is macOS 27.2 with Swift 6.4 in Swift 5 language mode; CI also compiles with Xcode 26.6 (SDK 26.5), so no macOS 27-only API without `#available`. `@State` with an initializer value must not be reassigned in `init`; assign non-`@State` stored properties first.
9. Crash-free code: `make check` (`Scripts/crash-guard.py`) fails on `fatalError`, `precondition`, `assert`, `assertionFailure`, `try!`, `as!`, force unwraps, implicitly unwrapped optionals, and `unowned`. Use `guard let`, failable `init?(coder:) { nil }`, optional outlets, and neutral fallbacks. `Scripts/crash-guard-allowlist.txt` is only for traps on programmer errors (dependency-injection registration); it must never grow for runtime input.
10. Subprocesses go through `Dreamder/Utils/Process/` (`ProcessRunner`, `ShellClient`, `GitCommandRunner`): argv arrays, sanitized environment, no shell string interpolation, no direct `Process()` in features. Git write commands are serialized per repository by `GitClient`.

## Commands

Run from `dreamder/`. `make` forces `DEVELOPER_DIR` to Xcode, because the command line tools lack the SwiftUI macros.

| Command | Purpose |
|---|---|
| `make check` | Run the crash guard over `Dreamder/` (pure Python, no build). CI runs it first. |
| `make build` | Resolve packages, stub the SwiftLint build plugin (its binary cannot load sourcekitd under Xcode 27), build the Debug app into `.build/xcode`. Prints only errors and the result; the full log is `.build/logs/build.log`. |
| `make run PROJECT_DIR=<folder>` | Build, quit the running copy, and open `<folder>` (default: this directory) in the app, visibly. For the user only; agents use `make headless`. |
| `make headless PROJECT_DIR=<folder>` | Build, quit the running copy, and open `<folder>` in headless mode: no Dock icon, never activates or steals focus, every window lives off-screen. All automation below works the same; screenshots capture the off-screen windows. |
| `make open FILE=<path>[:line:column]` | Open a file of an already open project in the running app's editor, optionally with the caret at a 1-based line and column (for screenshots). |
| `make toolwindow ID=<id>` | Show a tool window (`project`, `commit`, `structure`, `run`, `find`, `terminal`, `problems`, `git`, `languageServices`) in the frontmost project window of the running app. |
| `make screenshot [OUT=<dir>]` | Ask the running app to save PNGs of its windows (popups included) into `<dir>` (default `.build/screenshots/latest`). Works without Screen Recording permission. |
| `make action NAME=<selector>` | Send an action selector (for example `openSearchEverywhere:`) through the responder chain of the running app, then use `make screenshot` to see the result. |
| `make contextmenu [OUT=<dir>]` | Synthesize a right-click at the caret of the active editor, call the text view's context menu and dump the resulting menu items (recursively, with enabled state and shortcuts) into `<dir>/contextmenu.txt` (default `.build/contextmenu`). |
| `make annotate [OUT=<dir>]` | Toggle the Git blame annotation column of the active editor and write the new mode into `<dir>/annotate.txt` (default `.build/annotate`), then use `make screenshot` to see it. |
| `make menuitem NAME="Show History" [OUT=<dir>]` | Build the active editor's context menu and perform the item with that title (submenus included); reports whether the action was handled and lists the app's visible windows in `<dir>/menuitem.txt` (default `.build/menuitem`). |
| `make merge CMD="<command>[:<arg>...]"` | Drive the merge tool headlessly: `conflicts[:<project path>]`, `select:<path>`, `selectAdd:<path>`, `selectRange:<path>`, `acceptYours`, `acceptTheirs`, `mergeSelected`, `mergeFile:<path>`, `resolve:<block>:<left\|right\|ignored>`, `clickChip:<left\|result\|right>:<block>:<left\|right\|ignore>`, `applyNonConflicting:<left\|all\|right>`, `editResult:<text>`, `acceptLeft`, `acceptRight`, `apply`, `cancel`, `closeRevisions`, `closeConflicts`, `confirm:<yes\|no>`, `dump:<dir>` (writes `<dir>/merge.txt`). |
| `make release` | Build the Release configuration (ad-hoc signed) and zip it into `.build/Dreamder.zip`; this is what CI uploads. |
| `make test [FILTER=<Suite>]` | Run the `DreamderTests` unit tests (or one suite/class) with the test host in headless mode. Swift Testing suites run concurrently inside the test host; only suites with shared global state are `.serialized`. Full log in `.build/logs/test.log`. |
| `make coverage [TOP=<n>] [COVERAGE_CHECK=1]` | Run the unit tests headlessly with code coverage, then print per-file line coverage of the app sources in `Dreamder/` (lowest first, last `<n>` lines, default 40) and the total. Full table in `.build/logs/coverage.txt`, JSON in `.build/coverage.json`. With `COVERAGE_CHECK=1` (CI primary job) it fails when coverage drops below `Scripts/coverage-baseline.json` by scope (`Scripts/coverage-scopes.json`: `pure`, `viewModel`, `io` gated; `view` reported). |
| `make coverage-baseline` | Rewrite `Scripts/coverage-baseline.json` from the last `make coverage` run; commit it when coverage legitimately moves. |
| `make ui-test [ONLY=DreamderUITests/<Class>/<method>]` | Run UI tests. |

Testing is headless: agents NEVER run `make run`, `make ui-test`, or `open -a` on the app without `make headless`, so nothing appears on the user's screen. Only one build or test command may run at a time: they share `.build/xcode`. Unit tests write settings into a temporary directory, never into `~/Library/Application Support/Dreamder`.

## Layout

| Path | Contents |
|---|---|
| `Dreamder/Features/Islands/` | Islands theme tokens, tool window model (`ToolWindow.swift`), shared tool window header and island styling. |
| `Dreamder/Features/Islands/Workspace/` | The window root: tool window stripe, islands, resize handles, background image, layout persistence. |
| `Dreamder/Features/Islands/ToolWindows/` | Project, Structure, Find, Run, Terminal, Problems, and Language Services tool windows. |
| `Dreamder/Features/MainToolbar/` | Main toolbar widgets: project, VCS branch, Search Everywhere field, run, settings. |
| `Dreamder/Features/SearchEverywhere/` | Search Everywhere popup (double Shift), symbol index, matcher, Recent Files. |
| `Dreamder/Features/SourceControl/BranchesPopup/` | Git Branches popup and branch operations. |
| `Dreamder/Features/SourceControl/CommitToolWindow/`, `GitToolWindow/`, `DiffViewer/` | Commit tool window, Git log with commit graph, side-by-side diff window. |
| `Dreamder/Features/LSP/` | Language servers: automatic discovery (`Discovery/`), lifecycle states and restart (`LSPService.serverStates`), diagnostics into `WorkspaceDocument.diagnosticsStore`, completion, go to declaration, Show Usages, Quick Documentation, semantic tokens, inlay hints (`Editor/Decorations/InlayHintCoordinator.swift`). |
| `Dreamder/Features/MarkdownPreview/` | Markdown editor with live preview (in-repo Markdown→HTML renderer, sanitized raw HTML, `WKWebView`). |
| `Dreamder/Features/DreamderAutomation/` | Distributed-notification hooks behind `make screenshot`, `make action`, `make open`, and `make toolwindow`. |
| `Dreamder/Features/Matching/` | Port of IntelliJ's `MinusculeMatcher`/`NameUtil` (camel-hump matching, keyboard-layout fixing); used by Search Everywhere. |
| `Dreamder/Features/SourceControl/DiffEngine/` | Port of IntelliJ's diff and merge engine (by line, by word, by char, chunk optimizer, fair merge builder); `TextDiff` and `ThreeWayMerge` are built on it. |
| `Dreamder/Utils/Process/` | Process layer: `ProcessRunner`, `ProcessInvocation`, sanitized `ProcessEnvironment`, `GitCommandRunner`; `Utils/ShellClient/` wraps it for shell-syntax commands. |
| `DreamderTests/Utils/` | Test helpers: `withTempDir`/`makeTemporaryDirectory`, `FakeProcessRunner`, `TestClock`, `.isolatedDefaults`. |
| `Dreamder/Features/*` | Other editor features, restyled in place. |
| `Dreamder/IntelliJIcons.xcassets` | IntelliJ expui icons (Apache-2.0), with dark variants. |
| `Dreamder/Fonts/` | JetBrains Mono (OFL, `LICENSES/OFL-1.1-JetBrainsMono.txt`). |
| `DefaultThemes/` | Bundled editor themes, including the default `Islands Dark`. |
| `Scripts/` | Build and automation helpers used by the Makefile. |

Settings, themes, and editor state live in `~/Library/Application Support/Dreamder/`; the background image keys (`dreamder.backgroundImage.*`) live in the app's user defaults (`dev.dreamder.Dreamder`).

## Modernization state

Phase 3 execution plan (build-setting order with official citations, 12 file-ownership slices covering all 160 files, forbidden patterns, verification protocol): `local://phase3-plan.md`. The earlier phase 1–2 plan artifacts of the "Modernize" session are not available any more; the phase 2 contract is summarized in rules 2, 9 and 10 above. Liquid Glass decisions: all tool-window islands and popups use glass, the editor island and the active editor tab stay opaque.

| Phase | State |
|---|---|
| 1 Foundation (process layer, editor stability, LSP client requests, matcher, diff engine, test foundation, CI) | Done and verified: build, `make test`, `make check`, coverage gate, headless smoke, 60 s TypeScript LSP smoke. |
| 2 Observation and isolation | Partial: `CodeFileDocument`, `GitLogViewModel`, `GitConsoleLog` are `@Observable`; the other P2 slices are open. |
| 3 Swift 6 | App and `OpenWithDreamder` targets: Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, approachable concurrency, strict concurrency, 0 warnings (pure types are explicit `nonisolated`, AppKit callbacks hop with `Task { @MainActor }`/`assumeIsolated`, `isolated deinit`). Test targets: Swift 5 mode with strict concurrency (3 remaining warnings in `ThemeTests`/`RecentProjectsTests`); flip `SWIFT_VERSION` to 6.0 there next. |
| 4 Liquid Glass (islands, toolbar, popups, banners; active editor tab stays opaque) | Not started. |
| 5 IntelliJ ports (Search Everywhere ranking, branch popup order, git log filter, commit graph, find model, split tool windows) and test slices T1–T9 | Not started. |
| 6 Docs and final checks | Pending the phases above. |

Known leftovers: five unsafe concurrency escapes to retire in phase 3 (`ProcessExecution.UnsafeSendable`, `GitBlameCoordinator.WeakBox`, `InitializationGatedConnection`, `WorkspaceDocument.SearchState: @unchecked Sendable`, `ExcludedDirectories.registry` as `nonisolated(unsafe)`; plus two test doubles), view-scope coverage 10 %, Gatekeeper warning on downloads (ad-hoc signature, no notarization).
