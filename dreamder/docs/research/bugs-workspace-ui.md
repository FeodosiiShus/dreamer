# Workspace UI bug audit (read-only)

Scope: `dreamder/Dreamder/Features/{Islands,NavigatorArea,SearchEverywhere,Search,OpenQuickly,SplitView,StatusBar,MainToolbar,WindowCommands,Welcome}` and the Swift files directly in `dreamder/Dreamder/`. Nothing was built or run; every finding is derived from reading the quoted code. Callers outside the scope were read only to confirm a finding (`WorkspaceDocument.swift`, `WorkspaceDocument+FindAndReplace.swift`, `TaskManager.swift`, `CEActiveTask.swift` via grep).

Source marking: "URL verified" = the page was returned by a search of developer.apple.com in this session. "from memory" = official URL or wording not re-fetched in this session, treat as `[INFERENCE]` until opened.

| id | sev | title | confidence |
|---|---|---|---|
| WUI-1 | P0 | Replace on drop or cut-paste permanently deletes the folder that contains the dragged item | high |
| WUI-2 | P1 | Quit with unsaved documents never interrupts running tasks | medium |
| WUI-3 | P2 | Replace in Files rewrites files in place (truncate, then write) | medium |
| WUI-4 | P2 | Per-workspace UserDefaults keys are never removed | high |
| WUI-5 | P2 | Project filter walks the whole tree synchronously on the main actor | medium |
| WUI-6 | P2 | Symbol index applies every file-system delta in O(all symbols) on the main actor | medium |
| WUI-7 | P2 | Search Everywhere text search keeps running after the panel is gone | high |

---

## WUI-1 (P0, data loss) Replace deletes an ancestor of the source

`dreamder/Dreamder/Features/NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorViewController+NSOutlineViewDataSource.swift:136` and `:151`

```swift
if fileItemURL == destURL || fileItemURL == destParentURL {
    return false
}
...
try CEWorkspaceFile.fileManager.removeItem(at: destURL)
```

Same shape in `ProjectNavigatorViewController+Clipboard.swift:55` (guard) and `:137-140` (`removeItem(at: entry.destination)` then `moveItem`).

Failing sequence:
1. Project `P` contains `P/App/App` (a child named like its parent: `MyApp/MyApp`, `src/src`; on a case-insensitive volume also `dreamder/Dreamder`, the layout of this repository, `[INFERENCE]` about the volume format).
2. Drag the inner `App` onto the root row `P`. `destURL = P/App`. It equals neither the source `P/App/App` nor `destParentURL` `P`, so the guard at `:136` passes.
3. `fileExists(P/App)` is true, the dialog asks to replace `App`, the user confirms.
4. `removeItem(at: P/App)` at `:151` deletes the outer folder permanently (not Trash), including the item being dragged.
5. `moveFile` then fails because the source no longer exists; only an error alert remains.

Cut and paste reaches the same state: `:55` only rejects a target folder that lies inside the source, never a replaced destination that contains the source; `transfer` removes the destination (`:137`) and then `moveItem` (`:140`) fails.

Related gaps in the same function: the drop path has no "into own descendant" check at all (paste has it at `:55`), and because removal and move are two steps, any move or copy failure after `:151` loses the replaced item.

Standard: `FileManager.replaceItemAt(_:withItemAt:backupItemName:options:)`, https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:) (URL verified; the abstract "in a manner that ensures no data loss occurs" is from memory).

Fix sketch: before prompting, reject when the source is inside `destURL` (`Self.url(fileItemURL, isWithin: destURL)`) and when the drop folder is inside the source (`Self.url(destParentURL, isWithin: fileItemURL)`); replace through `replaceItemAt` (or move the old item aside, move, then trash the old item) so a failed move leaves the destination intact.

Test: `ProjectNavigatorControllerHarness` with folders `App`, `App/App`, file `App/App/keep.txt`, `confirmReplace = { _ in true }`, `acceptDrop(of: [App/App], sourceOperationMask: .move, onto: root)`; expect `false` and both paths still on disk. Today `App` is gone. Same with `cutToClipboard` + `paste(into: root)`.

Existing tests: `ProjectNavigatorDragDropTests.swift:146-215` and `ProjectNavigatorClipboardTests+CutTests.swift:71-95` cover confirm, decline and a locked destination; grep found no case where the source lies inside the replaced destination.

## WUI-2 (P1) Quit with unsaved documents skips task interruption

`dreamder/Dreamder/AppDelegate+Termination.swift:16` and `:61-63`

```swift
terminateTasks()
terminateLanguageServers()
...
let taskManagers = documentsController.documents
    .compactMap({ $0 as? WorkspaceDocument })
    .compactMap({ $0.taskManager })
```

Failing sequence:
1. A workspace has a running task and one unsaved file. Cmd-Q.
2. `applicationShouldTerminate` finds a dirty document and calls `closeAllDocuments(withDelegate:...)`.
3. The user saves or discards; every document closes. `WorkspaceDocument.close()` ends with `taskManager = nil` (`Features/Documents/WorkspaceDocument/WorkspaceDocument.swift:224`) and never calls `stopAllTasks()`.
4. The callback runs `terminateTasks()` (`:16`). The workspace documents are closed and their `taskManager` is nil, so `taskManagers` is empty and no signal is sent. `replyToTerminate(true)` follows after the language servers stop.

On the clean path (`:109`) the same call does interrupt the tasks, so behaviour depends on whether a file happened to be dirty. Not verified: whether `TaskManager`/`CEActiveTask` teardown or the pty close kills the children anyway, so "task processes survive the quit" is `[INFERENCE]`. Also on the clean path only `SIGINT` is sent, without waiting or escalation (`Features/Tasks/TaskManager.swift:242-245` states the process may ignore it).

Standard: `applicationShouldTerminate(_:)`, https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:) and `NSDocument.close()`, https://developer.apple.com/documentation/appkit/nsdocument/close() (both from memory: close removes the document from the document controller list).

Fix sketch: stop tasks inside `WorkspaceDocument.close()` before `taskManager = nil` (also covers closing a window), and in the quit flow await task exit with a deadline, escalating through `ProcessTree` before `replyToTerminate(true)`.

Test: `AppDelegate` with a fake `AppDocumentControlling` whose `closeAllDocuments` closes a real `WorkspaceDocument` that owns a fake active task and then invokes `documentController(_:didCloseAll:contextInfo:)` with `true`; expect the fake task to record an interrupt. Grep for `didCloseAll: (true|false)` in `DreamderTests` found no test of this path.

## WUI-3 (P2, latent data loss) Replace in Files is not crash-safe

`dreamder/Dreamder/Features/NavigatorArea/FindNavigator/FindReplaceEngine.swift:111-118`

```swift
do {
    try handle.truncate(atOffset: 0)
    try writer(handle, data)
} catch {
    try? handle.truncate(atOffset: 0)
    try? handle.write(contentsOf: original)
```

Failing sequence: Replace All over many files that are not open in an editor runs `FindFileRewriter.rewrite` in a task group. If the process ends between the truncate (`:112`) and the end of the write (`:113`), the file on disk is empty or partial; the restore branch only runs for thrown errors. Quit is one such end: `applicationShouldTerminate` neither awaits nor cancels a running replace and replies after at most the 2 s language-server timeout (`AppDelegate+Termination.swift:109-111`, `AppDelegate.swift` `languageServerShutdownTimeout`). A second gap: bytes written by another process between `Data(contentsOf:)` and `:112` are overwritten without a re-check.

What is correct here: ranges are re-validated against the current text (`FindReplaceEngine.edits`, a changed file yields `.stale`), and non-UTF-8 files fail with a message instead of being rewritten.

Standard: `NSData.WritingOptions.atomic`, https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic (URL verified, quote observed: "An option to write data to an auxiliary file first and then replace the original file with the auxiliary file when the write completes.").

Fix sketch: `try Data(updated.utf8).write(to: job.url, options: .atomic)` or write a sibling temp file and `replaceItemAt` to keep metadata; compare size and modification date with the values read before replacing. Confidence is medium because the in-place write with an explicit restore path looks intentional; the gap is process death.

Test: inject a `Writer` that reads the file size on entry; it observes 0 bytes for a non-empty original, which is the on-disk state if the process dies there. After the fix the original stays complete until the swap.

## WUI-4 (P2) Per-workspace UserDefaults keys grow without bound

`dreamder/Dreamder/Features/SearchEverywhere/SearchEverywhereRecentFiles.swift:121-123`, `dreamder/Dreamder/Features/NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorViewController.swift:154-156`, `dreamder/Dreamder/Features/Welcome/Model/RecentProjectsManager.swift:142-143`

```swift
private static func defaultsKey(_ key: String) -> String {
    "dreamder.recentFiles.\(key)"
}
...
defaults.removeObject(forKey: WorkspaceDocument.workspaceStateKey(for: workspaceURL))
```

Failing sequence: every opened project path creates `dreamder.recentFiles.<path>` (up to 50 absolute paths) and `NSOutlineView Items <path>` (`outlineView.autosaveName = folderUrl.path`). When a project is evicted from the 50 recent projects, removed, or the list is cleared, `discardWorkspaceState` removes only `workspaceState-...`. The other two families are never removed (grep over `Dreamder/` finds the key only in `defaultsKey`), so the standard domain grows with every distinct folder ever opened. `AGENTS.md` rule 15 records the consequence observed in the test host (process killed once the domain passes the CFPreferences limit), and `DreamderTests/Utils/TestHelpersTests.swift:185-189` shows the test helpers purge exactly these three key families themselves.

Standard: `UserDefaults.sizeLimitExceededNotification`, https://developer.apple.com/documentation/foundation/userdefaults/sizelimitexceedednotification (URL verified). The 4 MB figure itself: not documented in official sources that I verified.

Fix sketch: extend `discardWorkspaceState` to remove `dreamder.recentFiles.<path>` and `NSOutlineView Items <path>`, or store recent files inside the workspace-state dictionary so one removal covers everything.

Test: isolated defaults, open a workspace, record a recent file, call `removeRecentProject(path:)` (and separately mark 51 projects to force eviction); expect no key containing the project path. Today `dreamder.recentFiles.<path>` remains.

## WUI-5 (P2, hang risk) Project filter walks the whole tree on the main actor

`dreamder/Dreamder/Features/NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorViewController.swift:277-287` and `:319-320`

```swift
if let children = workspace?.workspaceFileManager?.childrenOfFile(item) {
    return children.contains { fileSearchMatches(filter, for: $0, sourceControlFilter: sourceControlFilter) }
}
```

Failing sequence: each filter change runs `handleFilterChange()`, which clears `filteredContentChildren`, reloads, and expands every included folder (`:287`). `visibleChildren(of:)` calls `fileSearchMatches` for every child; a folder whose name does not match recurses through `childrenOfFile` to the bottom of its subtree. The recursion is repeated at every level when the child folders are expanded, so the work is about (entries x depth) per keystroke, synchronously on the main actor. `fileSearchMatches` checks only `hiddenEntryNames`, not `exclusion(for:)` (which `expandIncludedFolders` does check), so excluded trees such as `node_modules` are still descended and listed. That `childrenOfFile` loads unvisited directories from disk is `[INFERENCE]` (its body is outside the scope and was not read).

Standard: main-thread responsiveness, https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app (from memory).

Fix sketch: build the match set off the main actor from `WorkspaceFileScope.enumerateFiles` (already cached and exclusion-aware), then filter children by set membership; debounce filter input; skip excluded folders in `fileSearchMatches`.

Test: harness with a few thousand nested folders plus an excluded `node_modules`; count `childrenOfFile` calls through an injected file manager while setting the filter. Expect at most one call per included folder and none under the excluded root. Existing filter tests (`ProjectNavigatorViewControllerTests.swift:349-442`) assert the visible result only.

## WUI-6 (P2) Symbol index delta is O(all symbols) on the main actor

`dreamder/Dreamder/Features/SearchEverywhere/SearchEverywhereSymbolIndex.swift:62-64`

```swift
let updatedKeys = Set(updated.map(\.workspacePathKey))
symbols.removeAll { removedPaths.covers($0.url) || updatedKeys.contains($0.url.workspacePathKey) }
symbols.append(contentsOf: changed)
```

Failing sequence: the class is `@MainActor`. Every file-system delta (each save, each generated file) runs this pass over the whole `symbols` array and builds a path string per symbol (`workspacePathKey`, `WorkspaceFileScope.swift:620-623`). If a search holds the previous array (`let symbols = index?.symbols` in `SearchEverywhereViewModel+Search.swift`), the mutation also copies the whole array. Each change of `symbols` then re-runs the search of every open panel (`SearchEverywhereViewModel.swift:68`). Cost per delta is proportional to project size instead of to the changed files; the wall-clock figure is `[INFERENCE]`, not measured.

Standard: same responsiveness guidance as WUI-5 (from memory).

Fix sketch: keep symbols as `[String: [SearchEverywhereSymbol]]` keyed by path key so a delta touches only changed files; compute the merged snapshot in the `@concurrent` scanner; coalesce bursts before publishing.

Test: seed an index with several hundred thousand synthetic symbols through a fake scope, emit a one-file delta, and assert through a counting key provider that work is proportional to the changed files.

## WUI-7 (P2) Text search task outlives the Search Everywhere model

`dreamder/Dreamder/Features/SearchEverywhere/SearchEverywhereViewModel.swift:84-88` and `SearchEverywhereViewModel+Search.swift:130`

```swift
isolated deinit {
    symbolsObservation?.cancel()
    changesObservation?.cancel()
    indexTask?.cancel()
}
```

Failing sequence: type a rare query on the Text tab of a large project and press Esc. The panel closes, `SearchEverywherePanelHost` drops the entry and the model deallocates. `textTask` (also `debounceTask`, `previewTask`) is not cancelled, and it captures `self` weakly, so `SearchEverywhereProjectSearch.textMatches` keeps reading up to 6000 files of up to 512 KB each until it finishes, then discards the result. Reopening and closing stacks further scans.

Standard: `Task`, https://developer.apple.com/documentation/swift/task (URL verified: tasks run immediately after creation; that dropping the reference does not cancel the task is from memory), and project rule 2 in `dreamder/AGENTS.md` (stored tasks are cancelled in `isolated deinit`).

Fix sketch: cancel `textTask`, `debounceTask` and `previewTask` in `isolated deinit`.

Test: model with a fake scope whose enumeration records cancellation; start a text search, release the model, expect the scan to observe cancellation. Grep for `textTask` in `DreamderTests` found no such test.

---

## Checked, nothing reported

- `SplitLayoutMath`, `SplitViewData`: no division by zero or NaN path found. Guards: `length.isFinite, length > 0`, `available > 0`, `lowerSum > available > 0` before the division, NaN/negative weights fall back to equal weights, `waterFill` pins at least one pane per round.
- Stale results: `SearchEverywhereViewModel` cancels `indexTask`/`textTask` per search and re-checks `Task.isCancelled` on the main actor; `OpenQuicklyViewModel` uses a generation counter; replace re-checks `isCurrentSearch(generation)`.
- Replace against a file changed since the search: ranges are re-matched, mismatches become `.stale` or `missing`.
- `SearchEverywherePanelHost`, `SearchEverywhereShiftMonitor`, `StructureViewModel`, `SearchEverywhereSymbolIndex`: tasks and monitors are weak-self and cancelled in `isolated deinit`.
- Not covered within the call budget: `FindNavigator` views and list controller, `StatusBar`, `MainToolbar`, `WindowCommands` (except `KeyWindowControllerObserver`), `Welcome` views, `WorkspaceSheets.swift`, `WindowObserver.swift`, `DreamderApp.swift`.
