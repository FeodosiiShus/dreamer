## Summary

Twelve findings in `dreamder/Dreamder/Features/SourceControl/`. The top ones:

- **SC-01 (P0):** clicking a merge chip after hand-editing the result pane silently overwrites the edits and clears the dirty flag.
- **SC-02 (P0):** the merge tool decodes stages as repaired UTF-8 and writes UTF-8 back, corrupting non-UTF-8 files.
- **SC-03 (P0):** shelve and unshelve reload open documents and discard unsaved editor edits, even when unshelve fails.
- **SC-04 (P0, security class):** ref names go to git as bare positionals; a fetched tag named `-f` turns Checkout into `git checkout -f`.
- **SC-05 (P1):** applying a merge result rewrites CRLF files as LF.
- **SC-06 (P1):** rolling back a renamed file deletes the new path and leaves the old one staged-deleted.

SC-01, 02, 05, 06, 07, 10 and 12 are high confidence; SC-03, 04, 08, 09 and 11 are medium because each rests on an assumption I name in the finding.

## Report: bugs-source-control.md

Paths are relative to `dreamder/Dreamder/Features/SourceControl/`.

### SC-01 · P0 data loss · Chip click after a manual edit discards the hand-written result
- **Where:** `MergeTool/MergeRevisionsViewModel.swift:128-132` and `:246-252`.
- **Quote:** `merge = updated` / `refreshContent(merge: updated)` and, in `refreshContent`, `resultText = merge.resultText` / `isResultEdited = false`.
- **Sequence:**
  1. Open Merge Revisions and type in the result pane; `userEditedResult` sets `isResultEdited = true`.
  2. Click any accept or ignore chip, or "Apply non-conflicting".
  3. `resultText` is regenerated from the block model, which never saw the typed text; the edits are gone.
  4. The flag is now false, so `requestCancel` (`:181`) and `MergeToolPresenter.swift:94` close or reload with no prompt.
- **Standard:** none external verified. It violates the module's own guard ("The result has unsaved changes that will be lost.").
- **Fix sketch:** when `isResultEdited` is true, confirm before `resolve`/`applyNonConflicting`, or disable the chips. Never clear the flag in `refreshContent` except on `load()`.
- **Confidence:** high. No test covers resolve-after-edit; the tests only cover `load()` after an edit and the presenter guard.
- **Test:** `load()`, `userEditedResult("draft\n")`, `resolve(firstBlock, .left)`; expect `resultText == "draft\n"` or a confirmation request.

### SC-02 · P0 data loss · Merge tool corrupts non-UTF-8 files
- **Where:** `MergeTool/MergeConflictRepository.swift:137` and `:120`; decoding is in `Utils/Process/GitCommandResult.swift` (`outputText`, about line 47).
- **Quote:** `try? await gitClient.run("show \(GitClient.logGraphQuote(object))")` and `try text.write(to: url, atomically: true, encoding: .utf8)`.
- **Sequence:**
  1. A Latin-1 file with byte `0xE9` conflicts.
  2. `git show :2:path` is decoded with `String(decoding:as: UTF8.self)`, which repairs the byte to U+FFFD. Only NUL counts as binary (`:140`).
  3. Apply, or Accept Left/Right inside the revisions window, writes the repaired text as UTF-8 and runs `git add`.
  4. Every non-ASCII byte in the worktree file and index is now `EF BF BD`.
- **Standard:** SE-0405 says String "already provides a way to transform data to valid Unicode by repairing invalid elements, but such a transformation is often not desirable" — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0405-string-validating-initializers.md
- **Fix sketch:** read stages with `runData` and validate with `String(validating:as:)`. Treat invalid input as non-mergeable, or carry a detected encoding and write back with it. Route in-window "accept side" through `git checkout --ours/--theirs`.
- **Confidence:** high.
- **Test:** `GitMergeFixture` with ISO-8859-1 content on both sides, `apply()`, compare bytes of the result with the expected Latin-1 bytes.

### SC-03 · P0 data loss · Shelve/unshelve throw away unsaved editor edits, even on failure
- **Where:** `GitToolWindow/Shelf/SourceControlManager+Shelf.swift:21-25` and `:54-55`; `SourceControlManager+DocumentReload.swift:9-14`.
- **Quote:** `} catch {` / `await finishShelfChange(urls: urls)` / `throw error`, then `reloadOpenDocuments(at: urls)`, then `try read(from: url, ofType: type)` … `updateChangeCount(.changeCleared)`.
- **Sequence:**
  1. `a.txt` is open with unsaved typing and is listed in a shelf.
  2. Unshelve fails with "would be overwritten" or "already exists" (shelf kept).
  3. The catch path still reloads `a.txt` from disk and clears the change count; the typing is gone with no prompt.
  4. The same reload runs after a successful shelve, where the stash only holds on-disk content.
- **Standard:** none verified (I did not fetch the NSDocument change-count docs).
- **Fix sketch:** save or refuse dirty documents before `stash push`/`stash apply`. On the error path reload nothing. On success reload only documents with no unsaved changes.
- **Confidence:** medium. I found no save step inside SourceControl; callers outside the folder were not checked.
- **Test:** open a `CodeFileDocument`, edit without saving, call `manager.unshelve` with a fake client that throws; expect the document content unchanged and still edited.

### SC-04 · P0 security class (low likelihood) · Ref names reach git as bare positionals
- **Where:** `Client/GitClient+BranchOperations.swift:116`, `:176`, `:180`, `:184`, `:251`; caller `BranchesPopup/BranchesPopupViewModel.swift:440`.
- **Quote:** `try await branchOpsCheckedRun(["checkout", revision])` · `["push", remote, "--delete", branch]` · `["tag", "-d", name]` · `["pull", mode, parts[0], parts[1]]`.
- **Sequence:**
  1. A remote publishes `refs/tags/-f`. git-check-ref-format: "a dash may appear at the beginning of a ref component".
  2. After fetch the popup lists tag `-f`.
  3. Checkout runs `git checkout -f`. git-checkout on `-f`: "This is used to throw away local changes".
  4. Uncommitted tracked changes are discarded. A remote branch `origin/--upload-pack=…` reaches `git pull … origin --upload-pack=…` the same way.
- **Standard:** gitcli: "You can use `--end-of-options` for this" — https://git-scm.com/docs/gitcli ; https://git-scm.com/docs/git-check-ref-format ; https://git-scm.com/docs/git-checkout
- **Fix sketch:** insert `--end-of-options` before every ref positional, or pass fully qualified `refs/tags/<name>` and `refs/heads/<name>`. `createTag` already uses `--`.
- **Confidence:** medium. `[INFERENCE]` that fetch stores such a tag and that the popup lists it; the user must also click the odd-named ref.
- **Test:** fixture creates `git update-ref refs/tags/-f HEAD`, dirties a tracked file, calls `branchOpsCheckoutRevision("-f")`; expect an error and the file unchanged.

### SC-05 · P1 · Applying a merge result converts CRLF and CR to LF
- **Where:** `DiffViewer/TextDiff.swift:155-157`; `MergeTool/ThreeWayMerge.swift:207-210`; `MergeTool/MergeConflictRepository.swift:120`.
- **Quote:** `normalized = (normalized as NSString).replacingOccurrences(of: "\r\n", with: "\n")` and `let text = resultLines.joined(separator: "\n")`.
- **Sequence:**
  1. A file stored with CRLF in the repository (no text conversion) conflicts.
  2. `ThreeWayMerge` splits all three sides with `TextDiff.lines`, which strips `\r`.
  3. Apply writes the LF-joined result and stages it; every line of the file changes.
  4. `hasTrailingNewline` is an OR over the three sides, so a deliberately removed final newline also comes back.
- **Standard:** gitattributes describes line-ending normalisation as a git attribute decision ("line endings are normalized to LF in the index" only when `text` is set) — https://git-scm.com/docs/gitattributes
- **Fix sketch:** detect the dominant separator of the "ours" stage and join with it, or keep each line's terminator in the model.
- **Confidence:** high. No CRLF case exists in `DreamderTests/Features/MergeTool`.
- **Test:** merge fixture with `a\r\nb\r\n` variants, `apply()`, expect the file to still contain `\r\n`.

### SC-06 · P1 · Rollback of a renamed file leaves it deleted
- **Where:** `CommitToolWindow/CommitToolWindowViewModel.swift:241-243`.
- **Quote:** `"restore --source=HEAD --staged --worktree -- \(GitClient.logGraphQuote(path))"`.
- **Sequence:**
  1. `git mv old.txt new.txt`; status reports a type-2 record (`<path><sep><origPath>`), so `fileURL` is `new.txt` and `originalFilename` is `old.txt`.
  2. Rollback restores only `new.txt` from HEAD, where it does not exist, so git removes it.
  3. `old.txt` is never restored; the tree now shows it as a staged deletion and the file is absent on disk.
- **Standard:** git-restore: "If a path is tracked but does not exist in the restore source, it will be removed to match the source." — https://git-scm.com/docs/git-restore ; record format — https://git-scm.com/docs/git-status
- **Fix sketch:** when `originalFilename` is set, pass both paths to the same `restore`.
- **Confidence:** high. The rollback tests only cover modified, added and untracked files.
- **Test:** fixture `git mv a.txt b.txt`, refresh, `rollback(manager.changedFiles)`; expect `a.txt` present, `b.txt` absent, status empty.

### SC-07 · P1 · Any branch whose name contains "HEAD" is hidden
- **Where:** `Client/GitClient+Branches.swift:27`.
- **Quote:** `guard line != "", !line.contains("HEAD") else { return false }`.
- **Sequence:**
  1. Create `fix/HEADER-parse`, or a branch whose upstream name contains HEAD.
  2. `getBranches()` drops the whole line, so `SourceControlManager.branches` lacks the branch.
  3. Branch pickers omit it, and `gitLogLocalBranchNames()` lets "New Branch" pass validation for an existing name, which then fails in git.
- **Standard:** ref-name rules permit the substring — https://git-scm.com/docs/git-check-ref-format
- **Fix sketch:** filter on the parsed `refname` field: skip `refs/remotes/*/HEAD` and the `(HEAD detached …)` pseudo-entry only.
- **Confidence:** high. `GitClientRemoteCoverageTests:199` only asserts that symbolic HEAD entries are absent.
- **Test:** fixture branch `feature/HEADER`; expect it in `getBranches()`.

### SC-08 · P1 · Partial-commit patch is built from raw worktree bytes
- **Where:** `CommitToolWindow/GitClient+CommitToolWindow.swift:70-71` and `:56`.
- **Quote:** `let worktree = try Data(contentsOf: directoryURL.appending(path: path))` and `"apply", "--cached", "--recount", "--whitespace=nowarn", patchURL…`.
- **Sequence:**
  1. `.gitattributes` has `* text eol=crlf`; the worktree file has CRLF, the blob has LF.
  2. Hunk coordinates come from `git diff HEAD`, which compares normalised content.
  3. The `+` lines are cut from raw bytes and keep `\r`.
  4. `git apply --cached` stores them, so the staged blob has mixed endings. Clean filters such as LFS mismatch in the same way.
- **Standard:** gitattributes: "When a matching file is added to the index, the file's line endings are normalized to LF in the index" — https://git-scm.com/docs/gitattributes . That `apply --cached` skips this conversion is **not documented in official sources** `[INFERENCE]`; the git-apply page did not match my quote search.
- **Fix sketch:** build the partial content in memory, then `git hash-object -w --path=<path> --stdin` and `git update-index --cacheinfo`, so filters run.
- **Confidence:** medium. `carriageReturnsStayPartOfEveryLine` asserts only the builder's byte fidelity.
- **Test:** repo with `eol=crlf`, exclude one of two hunks, `stageSelectedHunks`, expect `git cat-file blob :path` to contain no `\r`.

### SC-09 · P2 · Partial staging resets the index before the patch is known to apply
- **Where:** `CommitToolWindow/GitClient+CommitToolWindow.swift:40` and `:56`; `CommitToolWindow/CommitToolWindowViewModel.swift:189-203`.
- **Quote:** `_ = try await run(arguments: ["reset", "-q", "--", path])` … `"apply", "--cached", …`.
- **Sequence:**
  1. A file has earlier staged content, and whole-file adds and resets for other files have already run.
  2. `reset` drops the file's staged content.
  3. `apply --cached` fails, for example because of SC-08 or a save between the `diff` and the read at `:71`.
  4. The error is shown, but the index stays half-rewritten and the earlier staging is lost.
- **Standard:** none specific; plain atomicity.
- **Fix sketch:** run `git apply --cached --check` first, or stage into a temporary `GIT_INDEX_FILE` and swap on success.
- **Confidence:** medium; the failure trigger is a race or SC-08.
- **Test:** `FakeProcessRunner` failing `apply`; expect `git diff --cached` identical before and after.

### SC-10 · P2 · An excluded hunk is silently re-included once its content changes
- **Where:** `CommitToolWindow/CommitToolWindowViewModel.swift:125-127`; `CommitToolWindow/GitClient+CommitToolWindow.swift:39`.
- **Quote:** `excluded.formIntersection(ids)` / `excludedHunkIDs[file.id] = excluded.isEmpty ? nil : excluded` and `guard source.hunks.contains(where: { excluded.contains($0.id) }) else { return .wholeFile }`.
- **Sequence:**
  1. Untick one hunk; its id includes a content hash.
  2. Edit a character inside that hunk and save.
  3. `refreshHunks` drops the unknown id, so the file becomes fully included.
  4. Commit stages the whole file, including the hunk the user excluded.
- **Standard:** none.
- **Fix sketch:** key exclusions on the old-side range only, or mark the file "partially included, selection lost" and block the commit until reconfirmed.
- **Confidence:** high on the code path; severity is arguable because `theClientStagesNothingWhenNoExcludedHunkMatches` asserts the client-level `.wholeFile` outcome.
- **Test:** exclude a hunk, rewrite its line, `refreshHunks`; expect `isPartiallyIncluded(file)` to stay true or a user-visible flag.

### SC-11 · P2 · Renaming a shelf drops the stash before re-storing it
- **Where:** `Client/GitClient+Shelf.swift:178-179`.
- **Quote:** `_ = try await run(arguments: ["stash", "drop", "stash@{\(entry.index)}"])` / `_ = try await run(arguments: ["stash", "store", "--message", …, hash])`.
- **Sequence:**
  1. `drop` succeeds.
  2. `store` throws: `GitCommandRunner.run` checks cancellation after taking the gate, or a ref lock fails.
  3. The shelf commit is no longer referenced by the stash list.
  4. Separately, the index for `drop` comes from an earlier `stash list`, so a `git stash push` in between makes it drop the wrong entry.
- **Standard:** git-stash describes the stored object as "a dangling merge commit" until it is in the stash ref — https://git-scm.com/docs/git-stash
- **Fix sketch:** `stash store` first, then drop the old entry at `index + 1` after re-checking that `rev-parse stash@{n}` equals the hash.
- **Confidence:** medium.
- **Test:** fake runner failing the `store` call; expect the original hash still in `stash list`.

### SC-12 · P2 · A failed `git status` is shown as a clean tree and "All conflicts have been resolved"
- **Where:** `SourceControlManager+GitClient.swift:131-133`; `MergeTool/MergeConflictRepository.swift:50`; `MergeTool/MergeConflictsViewModel.swift:62-63`.
- **Quote:** `logger.error("Error fetching git status: \(error)")` / `setChangedFiles([])` and `guard let output = try? await gitClient.run("status --porcelain=v2 -z") else { return [] }`.
- **Sequence:**
  1. `git status` exits non-zero or the parser throws.
  2. The changed-file list is emptied and project-tree badges are cleared.
  3. During a merge the conflicts window shows "All conflicts have been resolved".
- **Standard:** none.
- **Fix sketch:** keep the previous list and surface an error state; let `entries()` throw and render the failure.
- **Confidence:** high.
- **Test:** fake runner returning exit 128 for `status`; expect a visible error rather than an empty list.

**Outside the owned folder (not counted):** `Utils/Process/GitCommandRunner.swift` treats `branch`, `tag`, `fetch`, `push`, `remote` and `worktree` as read-only, and `stream()` never takes the write gate. So `branch -m/-D`, `fetch a:b` and `runLive` commands are not serialised, despite AGENTS.md rule 10.

**Verdict:** incorrect. Three merge and shelf paths can lose or corrupt user content (SC-01, SC-02, SC-03) and ref names are not protected against option injection (SC-04). Overall confidence 0.8.
