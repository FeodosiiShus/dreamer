# Bug audit: Editor, Documents, CEWorkspace, CEWorkspaceSettings

Scope: `dreamder/Dreamder/Features/{Editor,Documents,CEWorkspace,CEWorkspaceSettings}`. Read-only review; nothing was built or executed, so every runtime consequence below follows from the quoted code and is not an observed run. Items marked `[INFERENCE]` depend on a link I did not read or run.

Sources fetched this session: `NSDocument.h` and `FSEvents.h` in the Xcode macOS SDK, `swiftlang/swift` `stdlib/public/core/LifetimeManager.swift`, `https://spec.editorconfig.org/`, and the resolved package checkouts under `dreamder/.build/xcode/SourcePackages/checkouts/` (CodeEditTextView, CodeEditSourceEditor). Apple URLs marked "(not re-fetched)" are cited from memory and should be opened before being quoted onward.

Coverage: read in full — `CodeFileDocument*`, `SaveActions`, `CodeFileContentLoad`, `FileEncoding`, `CodeFileTextViewBinder`, `EditorConfig/*`, `GitignoreMatcher`, `GitignoreRules`, `WorkspaceFileScope`, `WorkspaceDocument+FileScope`, `DirectoryEventStream`, `FileEventBatcher`, `RelocatedFileEvents`, `CEWorkspaceFileManager+DirectoryEvents`, `CEWorkspaceFileManager+FileManagement` (lines 1-300), `EditorActionCoordinator`, `EditorCommandModels`, `MoveLines`, `DeleteLines`, `EditorStateRestoration`, `UndoManagerRegistration`, `CodeFileViewSession`, `Editor+Closing`. Not reviewed: `DuplicateLines`, `JoinLines`, `OccurrenceSelection`, `CloneCaret`, `LineCommenter`, `BlockCommenter`, `Indexer/*`, `CEWorkspaceSettings/*`, `EditorLayout+StateRestoration`, `TabBar/*`, `Navigation/*`, `Decorations/*`, `GitAnnotations/*`, window controllers.

| id | sev | title | confidence |
|---|---|---|---|
| B-01 | P0 | Undo stack of a closed file survives "Don't Save" and external changes; Undo after reopen edits the wrong characters | medium |
| B-02 | P0 | Save actions edit the storage behind the undo manager when no text view is attached | medium |
| B-03 | P1 | One shared binder per document detaches the surviving split's text view | high |
| B-04 | P1 | FSEvents "must rescan" / dropped-event flags are discarded | high |
| B-05 | P1 | Save actions are not one undo group | high |
| B-06 | P1 | Case-only rename is rejected | medium |
| B-07 | P1 | `.editorconfig` properties are not re-resolved after a rename | high |
| B-08 | P2 | Case-only rename leaves the old path in `WorkspaceFileScope` | medium |
| B-09 | P2 | Pointer escapes `withUnsafeMutablePointer` | high |
| B-10 | P2 | Whole-file read and decode on the main actor, no size cap | medium |
| B-11 | P2 | Duplicate strips every occurrence of the extension from the name | high |

---

## B-01 (P0, data corruption on Undo) — stale undo stack after a tab is closed

`dreamder/Dreamder/Features/Editor/Models/Restoration/UndoManagerRegistration.swift:59-63`

```swift
func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
    for file in updatedItems where file.fileDocument == nil {
        managerMap.removeValue(forKey: file.url.absolutePath)
    }
}
```

This is the only place a manager is ever removed (`managerMap` is private). Every caller of `notifyObservers(updatedItems:)` passes directories: `CEWorkspaceFileManager+DirectoryEvents.swift:28-33` inserts the `parent` returned by `applyListing`, and `create`/`addFile`/`move` in `CEWorkspaceFileManager+FileManagement.swift` pass the anchor or parent folder. The map is keyed by file path, so the removal never matches. Content-only changes go through `notifyObservers(modifiedFiles:)`, which this class does not implement.

Other links in the chain:
- `Editor+Closing.swift:18-23` — closing a tab calls `updateChangeCount(.changeCleared)`, `close()`, `file.fileDocument = nil`; the undo manager is untouched.
- `Editor/Views/CodeFileView.swift:231` — `undoManager: undoRegistration.manager(forFile: editorInstance.file)` hands the old manager to the new editor.
- Package `CodeEditTextView/Utils/CEUndoManager.swift:69-90` — `undo()` replays `textView.replaceCharacters(in: mutation.inverse.range, with: mutation.inverse.string, …)` with the offsets recorded at edit time.

Failing sequence:
1. Open `a.txt`, type `abc` at offset 100.
2. Close the tab and choose not to save (or save, close, then let `git checkout`/a formatter change the file).
3. Reopen `a.txt`: a new `CodeFileDocument` is read from disk, the old `CEUndoManager` is reused.
4. ⌘Z: the inverse mutation deletes range `(100, 3)` of text the user never typed. Redo re-inserts `abc`, not the deleted characters.
If the edits were at the end of the file, the stored range lies past the new length; what the package does then was not checked `[INFERENCE]`.

Standard: the in-repo contract at `UndoManagerRegistration.swift:53-58` ("Managers need to be cleared when … the file is not open in any editors, the file is updated externally"); the package's own source (`CEUndoManager.registerMutation` is the only way the stack stays aligned with the storage, https://github.com/CodeEditApp/CodeEditTextView); `UndoManager.removeAllActions()` https://developer.apple.com/documentation/foundation/undomanager/removeallactions() (not re-fetched).

Fix sketch: drop the manager in `closeConfirmedTab` when the document is closed with discarded changes; implement `fileManagerModifiedFiles(_:)` in `UndoManagerRegistration` and remove managers for modified/removed file paths that have no open document; in `fileManagerUpdated` remove entries whose path is under an updated directory and no longer exists.

Test: host an editor on a temp file with the workspace's `UndoManagerRegistration`, insert text, call `editor.closeConfirmedTab(file:fromHistory:)`, then `#expect(registration.managerIfExists(forFile: url) == nil)`; second case: close after save, rewrite the file on disk, deliver the modified-files notification, expect the manager gone.

## B-02 (P0, data corruption on Undo) — save actions bypass the undo manager when no text view is attached

`dreamder/Dreamder/Features/Documents/CodeFileDocument/CodeFileDocument+SaveActions.swift:69-74`

```swift
} else {
    content.beginEditing()
    for edit in plan.edits {
        content.replaceCharacters(in: edit.range, with: edit.replacement)
    }
    content.endEditing()
```

The branch runs whenever `attachedTextView` is nil (`:51`). It changes the storage without `registerMutation`, while the file's `CEUndoManager` keeps its stack (see B-01). `selections` is `[]` in this branch (`:52`), so "keep trailing spaces on caret line" does not protect any line. Compare `CodeFileDocument+Support.swift:37-46`, where the reload path does register an undo mutation before `setString`.

The autosave task calls it regardless of visibility (`CodeFileDocument.swift:250-255`: sleep 2 s, then `applySaveActions()`, `autosave(…)`).

Failing sequence (autosave on, default "Modified lines" trimming):
1. In `x.swift` type `foo ` on line 1 (trailing space), then `bar` on line 3.
2. Switch to another tab within 2 s; the text view of `x.swift` is torn down and the binder detaches (`CodeFileTextViewBinder.destroy`) `[INFERENCE: I did not read the view code that tears the controller down on tab switch; B-03 is a confirmed route into the same branch]`.
3. The autosave task trims the space on line 1 directly in the storage.
4. Return to `x.swift`, ⌘Z: the `bar` group's inverse range is one UTF-16 unit too far right, so the wrong characters are removed.

Standard: same as B-01 (package source: undo replays recorded ranges).

Fix sketch: in the no-text-view branch either register the edits with `findWorkspace()?.undoRegistration.managerIfExists(forFile:)` as the reload path does, or clear that manager; alternatively skip trailing-space trimming for documents without a text view and keep only the final-newline edit registered.

Test: open a hosted session, type on two lines, call `textViewBinder.destroy()`, call `applySaveActions()`, re-host the document with the same `CEUndoManager`, undo once, expect the text to equal the pre-typing text plus save-action result — today the wrong range is replaced.

## B-03 (P1) — shared `CodeFileTextViewBinder` detaches the text view that is still on screen

`dreamder/Dreamder/Features/Documents/CodeFileDocument/CodeFileTextViewBinder.swift:26-31`

```swift
func destroy() {
    if let document, document.attachedController === boundController {
        document.attachedController = nil
    }
    boundController = nil
}
```

`CodeFileDocument.swift:79` creates one binder per document (`lazy var textViewBinder`), and `CodeFileView.swift:135` appends that same instance to every controller's coordinators. `prepareCoordinator` (`:13-16`) overwrites `boundController` with the latest controller. The package calls `destroy()` on all coordinators in `TextViewController.deinit` (`CodeEditSourceEditor/Controller/TextViewController.swift:271-280`).

Failing sequence:
1. Open `a.txt` (controller A: bound = A, attached = A).
2. Split so the same file is shown twice (controller B: bound = B, attached = B).
3. Close the first split; A deinitialises and calls `destroy()`: `attached (B) === bound (B)` → `attachedController = nil` although B is visible.
4. ⌘S in B: `applySaveActions` takes the no-text-view branch — B-02's undo desync, the caret line's trailing spaces are trimmed despite the setting, carets are not remapped. Everything else that reads `document.attachedTextView` also sees nil.

The test `destroyingABinderDoesNotDetachAnotherSplitsTextView` (`DreamderTests/Features/Documents/CodeFileSaveCaretTests+BinderTests.swift:23-36`) asserts the intended behaviour but assigns `attachedController` by hand, so `boundController` never moves as it does in production.

Standard: the project's own asserted behaviour (test above); package contract `TextViewCoordinator.destroy()` carries no controller argument, so a shared coordinator cannot tell which controller went away (https://github.com/CodeEditApp/CodeEditSourceEditor).

Fix sketch: create one binder per controller (in `CodeFileViewSession`), each holding its own controller weakly; the document keeps the set of live controllers and exposes the most recently focused one.

Test: host the same document twice with `document.textViewBinder` in both coordinator lists, close the first host, expect `document.attachedTextView === second.textView`.

## B-04 (P1) — FSEvents rescan and dropped-event flags are thrown away

`dreamder/Dreamder/Features/CEWorkspace/Models/DirectoryEventStream.swift:207-213`

```swift
static func events(fromFlags raw: FSEventStreamEventFlags) -> Set<FSEvent> {
    var events: Set<FSEvent> = []

    if raw == 0 {
        events.insert(.changeInDirectory)
    }
    if raw & UInt32(kFSEventStreamEventFlagRootChanged) > 0 {
```

The function tests only RootChanged, ItemChangeOwner, ItemCreated, ItemCloned, ItemModified, ItemRemoved and ItemRenamed. A flag word of `kFSEventStreamEventFlagMustScanSubDirs` (alone or with `UserDropped`/`KernelDropped`) yields an empty set, and `events(fromPayload:flags:)` then emits nothing for that path. A search for `MustScanSubDirs|UserDropped|KernelDropped` in `Dreamder/` and `DreamderTests/` has no matches.

Failing sequence: a burst the kernel or the client buffer cannot keep (large `git checkout`, `npm install`, unzip) → FSEvents reports the root with `MustScanSubDirs` → both consumers (`CEWorkspaceFileManager.processFileSystemEvents` and `WorkspaceFileScope.handle(events:)`) receive nothing → the project tree and the cached file list used by Search Everywhere, Open Quickly and Find in Files stay stale until some later event or a manual reload.

Standard: `FSEvents.h` in the macOS SDK, lines 385-414: "Your application must rescan not just the directory given in the event, but all its children, recursively" and "Your code need only check for the kFSEventStreamEventFlagMustScanSubDirs flag". Web copy: https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags (not re-fetched).

Fix sketch: add `FSEvent.mustRescan`; map `MustScanSubDirs` to it; `WorkspaceFileScope.handle` treats it like `.rootChanged` (`reload()`), `RelocatedFileEvents` adds the path and every loaded descendant directory to `treeParents`.

Test: `#expect(DirectoryEventStream.events(fromFlags: UInt32(kFSEventStreamEventFlagMustScanSubDirs)) == [.mustRescan])`; a `WorkspaceFileScope` with a fake file system receives that event and yields `.reset`.

## B-05 (P1) — save actions produce one undo step per trimmed line

`dreamder/Dreamder/Features/Documents/CodeFileDocument/CodeFileDocument+SaveActions.swift:63-65`

```swift
for edit in plan.edits {
    textView.replaceCharacters(in: edit.range, with: edit.replacement, skipUpdateSelection: true)
}
```

No `beginUndoGrouping()`/`endUndoGrouping()` surrounds the loop; `EditorActionCoordinator.swift:178-183` does wrap its loop. In the package, `CEUndoManager.registerMutation` (`:183-188`) appends to the current group only when `isGrouping || shouldContinueGroup(...)`, and for deletions `shouldContinueGroup` (`:230-235`) requires `lastMutation.range.location == mutation.range.max`. Trims on different lines are never adjacent, so each becomes its own group.

Failing sequence: three modified lines end in spaces → ⌘S → three undo groups. ⌘Z restores the spaces of one line only (an invisible change); the user's own last edit needs four presses. With autosave on, every 2 s autosave inserts such groups between the user's typing groups.

Standard: package source above; `UndoManager.beginUndoGrouping()` https://developer.apple.com/documentation/foundation/undomanager/beginundogrouping() (not re-fetched).

Fix sketch: wrap the loop in `textView.undoManager?.beginUndoGrouping()` / `endUndoGrouping()` exactly as `EditorActionCoordinator.apply` does.

Test: hosted session, text `"a  \nb  \n"` with both lines marked modified and the caret on a third line, `applySaveActions()`, one `undo()`, expect `"a  \nb  \n"`.

## B-06 (P1) — renaming a file to the same name in a different case is refused

`dreamder/Dreamder/Features/CEWorkspace/Models/CEWorkspaceFileManager+FileManagement.swift:281-283`

```swift
guard !fileManager.fileExists(atPath: newLocation.path(percentEncoded: false)) else {
    throw FileManagerError.destinationFileExists
}
```

and `CEWorkspaceFile.swift:252-258` (`validateFileName`): `!FileManager.default.fileExists(atPath: self.url.deletingLastPathComponent().appending(path: newName).path)`.

Failing sequence: rename `readme.md` to `README.md` in the project navigator on a case-insensitive volume. The existence check for the new name resolves to the file being renamed, so `validateFileName` returns false and `move` throws `destinationFileExists` `[INFERENCE: not executed; depends on the volume being case-insensitive]`.

Standard: Apple File System Guide FAQ — APFS on macOS defaults to the case-insensitive variant: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/APFS_Guide/FAQ/FAQ.html (not re-fetched).

Fix sketch: in both checks treat the destination as free when it resolves to the source (`URLResourceKey.fileResourceIdentifierKey` equal for old and new URL); `FileManager.moveItem` performs a case-only rename.

Test: temp dir with `readme.md`, `try await manager.move(file:to: dir/README.md)`, expect no throw and `contentsOfDirectory == ["README.md"]`; the existing test at `CEWorkspaceFileManagerFileManagementTests.swift:68` covers only a distinct existing target.

## B-07 (P1) — `.editorconfig` values stay those of the old path after a rename

`dreamder/Dreamder/Features/Documents/CodeFileDocument/CodeFileDocument.swift:197`

```swift
editorConfig = fileURL.map { EditorConfigResolver().properties(for: $0) } ?? .empty
```

This line inside `apply(_:detectedIndent:)` (run from `read`) is the only assignment of `editorConfig`. `NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorViewController+Tabs.swift:72-75` moves the live document to the renamed file with `document.fileURL = newFile.resolvedURL` and nothing re-resolves.

Failing sequence: `.editorconfig` has `[*.txt] trim_trailing_whitespace = true` and `[*.md] trim_trailing_whitespace = false`. Open `notes.txt`, rename it to `notes.md` in the navigator, add a Markdown hard break (two trailing spaces), save. `SaveActions(editorConfig:settings:)` still sees `trimTrailingWhitespace == true` → `.allLines` and removes the trailing spaces across the file. Indent resolution uses the stale values too. The same staleness applies when `.editorconfig` itself is edited while documents are open.

Standard: https://spec.editorconfig.org/ — "Section names in EditorConfig files are filepath globs", applied to the file's path.

Fix sketch: resolve in a `fileURL` `didSet` (or a method called from both `apply` and the rename handover); additionally re-resolve open documents when a `.editorconfig` under the workspace changes.

Test: temp dir with that `.editorconfig`, open `notes.txt`, set `document.fileURL` to `notes.md`, expect `document.editorConfig.trimTrailingWhitespace == false`.

## B-08 (P2) — a case-only rename leaves both names in the file scope

`dreamder/Dreamder/Features/CEWorkspace/Models/WorkspaceFileScope.swift:329-333` and `:150-152`

```swift
guard let entry = fileSystem.entry(at: url) else {
    removed.append(url)
    continue
}
```
```swift
for url in updated where paths.insert(url.workspacePathKey).inserted {
    files?.append(url)
}
```

Failing sequence: `a.txt` is renamed to `A.txt` (Finder, `git mv`) on a case-insensitive volume. FSEvents reports both paths. `DiskWorkspaceFileSystem.entry(at:)` (`:50-53`) still resolves the old spelling, so it is classified as an existing file instead of removed `[INFERENCE: not executed]`; the new spelling is appended because `workspacePathKey` is case-sensitive. Search Everywhere, Open Quickly and Find in Files list the file twice until the next invalidation.

Standard: same APFS FAQ as B-06 (not re-fetched).

Fix sketch: in `handle(events:)`, for `.itemRenamed` compare `entry.name` with the on-disk name (`URLResourceKey.nameKey` or the parent listing) and treat a mismatch as removed.

Test: fake `WorkspaceFileSystem` whose `entry(at:)` answers for both spellings but reports the canonical `name`; send rename events for both; expect one entry.

## B-09 (P2, latent undefined behaviour) — pointer returned out of `withUnsafeMutablePointer`

`dreamder/Dreamder/Features/CEWorkspace/Models/DirectoryEventStream.swift:99`

```swift
let contextPtr = withUnsafeMutablePointer(to: &context) { ptr in UnsafeMutablePointer(ptr) }
```

`contextPtr` is then passed to `FSEventStreamCreate`. It works today only because `context` is still on the stack; the compiler is free to pass a temporary copy to the closure.

Standard: `swiftlang/swift` `stdlib/public/core/LifetimeManager.swift:106-108`: "The pointer argument to `body` is valid only during the execution of `withUnsafeMutablePointer(to:_:)`. Do not store or return the pointer for later use." https://github.com/swiftlang/swift/blob/main/stdlib/public/core/LifetimeManager.swift

Fix sketch: move the `FSEventStreamCreate` call inside the closure and return the stream ref (`withUnsafeMutablePointer(to: &context) { FSEventStreamCreate(…, $0, …) }`).

Test: none can show UB deterministically; the fix is verified by the existing stream tests continuing to pass.

## B-10 (P2) — opening and reloading read and decode the whole file on the main actor

`dreamder/Dreamder/Features/Documents/CodeFileDocument/CodeFileDocument+Support.swift:53-58`

```swift
private func reloadFromDiskIfUnedited() -> Bool {
    guard fileModificationDate != getModificationDate(), !isDocumentEdited else { return false }
    fileModificationDate = getModificationDate()
    if let fileURL, let fileType {
        try? read(from: fileURL, ofType: fileType)
```

Also `Editor/Models/Editor/Editor.swift:287` (`try item.file.loadCodeFile()`) → `CEWorkspaceFile.swift:266-279` → `CodeFileDocument(contentsOf:ofType:)`, and `CodeFileDocument.swift:183-188` where `read(from:ofType:)` classifies, runs `IndentDetector` and then `MainActor.assumeIsolated`. `CodeFileContentLoad.classify` decodes the complete data even when `FileSizeLimit.exceedsIntelligenceLimit` is true; the 10 MB limit only sets a read-only flag. `apply` additionally walks every parent directory reading `.editorconfig` (`CodeFileDocument.swift:197`).

Failing sequence: open (or have a tool rewrite) a multi-hundred-megabyte log; the main thread performs file read, encoding detection, text-storage creation and, on reload, a full-content undo mutation before the next frame. Duration scales with file size; not measured here.

Standard: `dreamder/AGENTS.md` rule 12 (main-thread blocking stalls the host); Apple, "Understanding hangs in your app" https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app (not re-fetched).

Fix sketch: read and classify in a `@concurrent` helper (the classification is already `nonisolated` and `Sendable`), hop to the main actor only for `apply`; cap the decoded prefix for files above the intelligence limit.

Test: inject a slow reader/classifier seam and assert the main-actor heartbeat keeps running while a load is in flight.

## B-11 (P2, cosmetic) — Duplicate removes every occurrence of the extension from the base name

`dreamder/Dreamder/Features/CEWorkspace/Models/CEWorkspaceFileManager+FileManagement.swift:219-223`

```swift
let fileExtension = fileUrl.pathExtension.isEmpty ? "" : ".\(fileUrl.pathExtension)"
let fileName = fileExtension.isEmpty ? previousName :
previousName.replacingOccurrences(of: fileExtension, with: "")
fileUrl = fileUrl.deletingLastPathComponent().appending(path: "\(fileName) copy\(fileExtension)")
```

Failing sequence: duplicate `my.swiftlint.swift` → `.swift` is removed twice → the copy is named `mylint copy.swift`; `foo.json5.json` → `foo5 copy.json`. No data is lost (the loop continues until the name is free).

Standard: `replacingOccurrences(of:with:)` replaces all occurrences: https://developer.apple.com/documentation/foundation/nsstring/replacingoccurrences(of:with:) (not re-fetched).

Fix sketch: `let fileName = fileUrl.deletingPathExtension().lastPathComponent`.

Test: temp dir with `my.swiftlint.swift`, `try manager.duplicate(file:)`, expect `my.swiftlint copy.swift` to exist.

---

## Checked and not reported

- `NSDocument.h:114` documents `init(contentsOf:ofType:)` as `init`, `read(from:ofType:)`, then `setFileURL`. `CodeFileDocument.apply` reads `fileURL` during `read` to resolve `.editorconfig`. The tests that depend on this (`CodeFileDocumentStateTests.swift:296-345`) use `init(for:withContentsOf:ofType:)`, while production (`CEWorkspaceFile.swift:276`) uses `init(contentsOf:ofType:)`. Whether `fileURL` is set during the first read on the production path was not run; worth one test through `loadCodeFile()`.
- `SourceControlManager+DocumentReload.swift` `reloadContentDiscardingEdits()` drops unsaved edits by design (outside the owned folders).
- Gitignore matcher: negation, anchoring, directory-only, `**`, trailing-space and `\r` handling, parent-directory exclusion and `.git/info/exclude` precedence match https://git-scm.com/docs/gitignore as I recall it (page not re-fetched). `core.excludesFile` (global ignore) is not consulted — a gap, not a matching error.
- EditorConfig parser, glob translation and indent post-processing: no defect found. `insert_final_newline = false` does not strip an existing final newline and `end_of_line` is used only for the appended newline; both are narrower than the spec text.
- `MoveLines`, `DeleteLines`, `EditorLineIndex`: CRLF and first/last-line cases hold on reading.
- `WorkspaceFileScope` caches are bounded by file and directory counts and reset on `.gitignore` changes.
