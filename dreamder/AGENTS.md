# dreamder

Native macOS code editor in Swift, forked from an MIT-licensed native editor (`LICENSE.md` keeps its notice), restyled and extended to look and work like IntelliJ IDEA's New UI (Islands Dark) and like Flint (`/Users/oleksandr/WebstormProjects/Flint`, the product reference). The bundled IntelliJ assets (expui icons, Islands themes, JetBrains Mono) come from the IntelliJ sources in this repository. CI: `.github/workflows/dreamder.yml` at the repository root builds the Release app (`make release`, artifact `Dreamder`) and runs `make test`.

## Rules

1. NEVER write comments or doc comments in new or edited code; leave existing comments alone.
2. Follow the existing patterns (ObservableObject view models, `@EnvironmentObject` injection, `@AppSettings`, AppKit window controllers). Do not introduce a second convention. Packages named `CodeEdit*` (`CodeEditSourceEditor`, `CodeEditTextView`, `CodeEditLanguages`, `CodeEditKit`, `CodeEditSymbols`) are third-party dependencies and keep their names.
3. Colors, metrics, and fonts of new chrome come from `Dreamder/Features/Islands/Islands.swift` (IntelliJ Islands Dark values). Icons are IntelliJ expui SVGs in `Dreamder/IntelliJIcons.xcassets`, addressed as `Image("<set>/<name>")` (for example `toolwindows/project_20`, `vcs/branch`, `general/search`); the full list is printed by `ls Dreamder/IntelliJIcons.xcassets/*/`.
4. Tool windows are identified by `ToolWindowID` and shown through `WorkspaceDocument.toolWindowManager` (`Dreamder/Features/Islands/ToolWindow.swift`).
5. Flint is GPL-3.0 and written in Rust: use it as a behavior and visual reference only, never copy its code or assets.
6. NEVER add a Swift package without user approval.
7. New files inside `Dreamder/`, `DreamderTests/`, and `DreamderUITests/` are picked up automatically (file-system synchronized groups); never hand-edit `project.pbxproj` to add files.
8. The SDK is macOS 27.2 with Swift 6.4 in Swift 5 language mode. `@State` with an initializer value must not be reassigned in `init`; assign non-`@State` stored properties first.

## Commands

Run from `dreamder/`. `make` forces `DEVELOPER_DIR` to Xcode, because the command line tools lack the SwiftUI macros.

| Command | Purpose |
|---|---|
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
| `make coverage [TOP=<n>]` | Run the unit tests headlessly with code coverage, then print per-file line coverage of the app sources in `Dreamder/` (lowest first, last `<n>` lines, default 40) and the total. Full table in `.build/logs/coverage.txt`. |
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
| `Dreamder/Features/*` | Other editor features, restyled in place. |
| `Dreamder/IntelliJIcons.xcassets` | IntelliJ expui icons (Apache-2.0), with dark variants. |
| `Dreamder/Fonts/` | JetBrains Mono (OFL, `LICENSES/OFL-1.1-JetBrainsMono.txt`). |
| `DefaultThemes/` | Bundled editor themes, including the default `Islands Dark`. |
| `Scripts/` | Build and automation helpers used by the Makefile. |

Settings, themes, and editor state live in `~/Library/Application Support/Dreamder/`; the background image keys (`dreamder.backgroundImage.*`) live in the app's user defaults (`dev.dreamder.Dreamder`).
