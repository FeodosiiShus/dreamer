Nothing was built or run; every finding comes from reading the code. Three things were not re-fetched and are marked `[INFERENCE]` where used: the LSP specification wording (two greps of the 3.17 page returned nothing), the Apple `URL.path(percentEncoded:)` page, and `CodeFileDocument` internals. Line numbers are grep-confirmed for `LSPService.swift`, `LSPService+Crash.swift`, `LSPService+Documents.swift`, `LSPTextPositionConverter.swift` and the two caller files; the rest were counted from raw reads and may be off by a line or two.

Top findings:
- **LSP-01 (P0 security):** an untrusted workspace still launches rust-analyzer, which runs `build.rs` and proc macros.
- **LSP-02 (P1):** servers are never shut down on window close when the workspace path contains a space or non-ASCII character.
- **LSP-03 (P1):** after a crash restart, edits typed just before the reopen are sent twice, so the server's text diverges.
- **LSP-04 (P1):** rename and `workspace/applyEdit` apply edits without checking the document version or pending edits.
- **LSP-05 / LSP-06 (P1):** crash-restart races lose `didOpen` for open documents or send it for closed ones.

LSP spec base URL used below: `https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/` (abbreviated `SPEC`).

# LSP bug audit — `dreamder/Dreamder/Features/LSP/`

## LSP-01 — P0 (security) — Untrusted workspaces still start servers that execute workspace code
- **Where:** `Discovery/LanguageServerDiscovery+TypeScript.swift:19`; server start without a trust gate at `Service/LSPService+Documents.swift:30`.
- **Quote:**
  ```swift
  guard typeScriptLanguages.contains(language) else { return nil }
  ```
- **Sequence:**
  1. The user has `rust-analyzer` on the global PATH and opens an untrusted clone containing a `build.rs`.
  2. Opening any `.rs` file calls `openDocument` → `startServer`.
  3. Discovery returns the global binary; trust only removes the workspace bin directories from the search path.
  4. `createServer` launches it with `rootUri` set to the workspace and no restricting options, because only TypeScript gets any.
  5. rust-analyzer runs the build script and proc macros.
- **Standard:** https://rust-analyzer.github.io/book/security.html (fetched): "At the moment, rust-analyzer assumes that all code is trusted … proc macros and build scripts are executed by default", plus `.cargo/config` and `rust-toolchain.toml` can override `rustc` with an arbitrary executable. Project rule in `dreamder/AGENTS.md`: "Anything that executes workspace-controlled code must consult it".
- **Fix:** refuse to start servers that execute workspace code when `isTrusted` is false, and reuse `SafeModeNotifier`. Disabling build scripts and proc macros alone is not enough, given the `rustc` overrides.
- **Confidence:** medium. The code path is certain; it may be a design gap rather than a slip. Other servers (gopls, jdtls, sourcekit-lsp) were not checked against their documentation.
- **Test:** a fixture service with `isTrusted = false` and a discoverable fake `rust-analyzer`; assert no server is created for `.rust`.

## LSP-02 — P1 — `closeWorkspace` never matches workspaces whose path needs percent-encoding
- **Where:** `Service/LSPService+Shutdown.swift:16`; caller `Features/Documents/Controllers/DreamderDocumentController.swift:154`; key built at `Service/LSPService+Documents.swift:15`; `Utils/Extensions/URL/URL+absolutePath.swift:12`.
- **Quote:**
  ```swift
  if let workspace = document as? WorkspaceDocument, let path = workspace.fileURL?.absoluteURL.path() {
      lspService.closeWorkspace(path)
  // key side:
  let workspacePath = workspace.fileURL?.absolutePath   // absoluteURL.path(percentEncoded: false)
  ```
- **Sequence:**
  1. Open `/Users/me/My Project` and a `.ts` file; the client key holds `"/Users/me/My Project…"`.
  2. Close the window; `closeWorkspace` receives `"/Users/me/My%20Project…"`.
  3. Every `where key.workspacePath == workspacePath` filter is empty.
  4. The server process, event and termination tasks, watched-files forwarder, `serverStates` and diagnostics all survive until the app quits.
- **Standard:** https://developer.apple.com/documentation/foundation/url/path(percentencoded:) — `[INFERENCE]` the default `percentEncoded: true` is recalled, not fetched. The repo's own `absolutePath` helper exists to pass `false`.
- **Fix:** pass `workspace.fileURL?.absolutePath` at the call site.
- **Confidence:** high.
- **Test:** open a workspace in a temp directory named `my project` through the document controller with a fixture service, remove the document, and expect `languageClients` to be empty. Existing tests call `closeWorkspace(workspace.path)` directly, so they bypass the caller.

## LSP-03 — P1 — Pending edits are sent twice after a server is reopened
- **Where:** `LanguageServer/Capabilities/LanguageServer+DocumentSync.swift:17-32`, contrast `:129`; `Features/DocumentSync/LSPContentCoordinator.swift:46-49`.
- **Quote:**
  ```swift
  guard resolveOpenCloseSupport(), let content = getIsolatedDocumentContent(document) else {
  …
  try await lspInstance.textDocumentDidOpen(DidOpenTextDocumentParams(textDocument: textDocument))
  updateIsolatedDocument(document)
  ```
- **Sequence:**
  1. An incremental-sync server crashes while the user keeps typing. `serverTerminated` does not tear down the document objects, so the coordinator keeps recording into `pendingElements`.
  2. After the backoff, `reopen` → `openDocument` snapshots the full text, which already contains the keystroke typed under 250 ms ago.
  3. `setUp` points the coordinator at the new server without discarding `pendingElements`.
  4. The batch timer fires and `flushPendingChanges` sends that keystroke again as an incremental `didChange`.
  5. The server now has the character twice, and every later range is shifted until a full reload.
- **Standard:** `SPEC#textDocument_didChange` — the server's content must equal the open text plus the changes applied in order. `[INFERENCE]` wording not re-fetched.
- **Fix:** call `document.languageServerObjects.textCoordinator.discardPendingChanges()` in the same main-actor turn that reads `content` in `openDocument`, as `reloadDocument` already does.
- **Confidence:** high.
- **Test:** with `SyncTestServer.makeIncremental`, open with `batchInterval: .seconds(60)`, record an edit, call `server.openDocument(document)` again on a fresh server, flush, and expect no `didChange`. `reloadInvalidatesTheCacheAndDiscardsPendingEdits` covers only the reload path.

## LSP-04 — P1 — Workspace edits ignore the document version and unflushed edits
- **Where:** `Service/LSPWorkspaceEditing.swift:162-163`; `Service/LSPService+ClientRequests.swift:160-170`; `Features/Rename/RenameFlow.swift:42-46`.
- **Quote:**
  ```swift
  case let .textDocumentEdit(edit):
      return .editText(uri: edit.textDocument.uri, edits: edit.edits)
  …
  let resolved = try LSPTextEditApplier.resolve(edits, in: storage.string)
  ```
- **Sequence:**
  1. The user confirms a rename; `backend.rename` is awaited with the popup gone and the editor editable.
  2. The user types a line above the symbol.
  3. The response, computed for the old version, is resolved against the new text.
  4. The wrong ranges are replaced and the result reports `applied: true`.
  The same happens for a server-initiated `workspace/applyEdit` that arrives while a 250 ms batch is still pending.
- **Standard:** `SPEC#textDocumentEdit` — the identifier is versioned "to allow clients to check the text document version before an edit is applied". `[INFERENCE]` wording not re-fetched.
- **Fix:** carry `textDocument.version` into `.editText`. In `editOpenDocument`, fail with `applied: false` when it differs from `openFiles.documentVersion(for:)` or `textCoordinator.hasPendingChanges` is true. For rename, snapshot the text and reuse the `isCurrent` check that `FormattingService` already has.
- **Confidence:** high.
- **Test:** call `WorkspaceEditApplier.apply` with `documentChanges` at version 0 after one flushed edit (version 1); expect `applied == false` and unchanged text.

## LSP-05 — P1 — Open documents lose their server when another start wins the restart race
- **Where:** `Service/LSPService+Crash.swift:64`; `Service/LSPService.swift:297`.
- **Quote:**
  ```swift
  guard !Task.isCancelled, self.languageClients[key] == nil else { return }
  …
  languageClients[key] = server
  lostDocuments.removeValue(forKey: key)
  ```
- **Sequence A:**
  1. `a.ts` and `b.ts` are open and the server crashes; the restart task sleeps 2 s.
  2. The user opens `c.ts`; `openDocument` → `startServer` launches a server immediately.
  3. The restart task wakes, sees a client, and returns without `reopen`.
  4. `a.ts` and `b.ts` never get `didOpen`, and a later `restartServer` reads only the new server's `openFiles`.
- **Sequence B:** after two crashes `lostDocuments[key]` holds `a.ts` and `b.ts`; opening `c.ts` starts a server and line 297 drops the list.
- **Standard:** `SPEC#textDocument_didOpen` — a document the client manages must be announced with `didOpen`. `[INFERENCE]` wording not re-fetched.
- **Fix:** have `launchServer` return the pending documents (captured list or `lostDocuments[key]`) to be reopened by whichever caller wins.
- **Confidence:** high on the code. No test references `lostDocuments`, and none of the test names I searched for covers this case.
- **Test:** crash with `backoff: .seconds(60)`, call `openDocument` for a third file, then expect the new connection's opens to include all three URIs.

## LSP-06 — P1 — A document closed during backoff or restart is reopened and never closed
- **Where:** `Service/LSPService+Crash.swift:42, 61-65, 18-26`, also `:10`; `Service/LSPService+Documents.swift:61-65`.
- **Quote:**
  ```swift
  let documents = server.openFiles.documents
  …
  restartTasks[key] = Task { [weak self] in
      …
      await self.performAutomaticRestart(key, documents: documents, name: name)
  ```
- **Sequence:**
  1. The server crashes and the task captures `[a, b]` strongly.
  2. The user closes `b.ts`; `closeDocument` prunes only `openDocumentURIs` and `lostDocuments`, and finds no client.
  3. After the backoff, `reopen` inserts `b` into `openDocumentURIs` and sends `didOpen` for it; no `didClose` ever follows.
  4. Reopening `b.ts` later sends a second `didOpen`, because `openFiles` holds the old document weakly and it is gone.
- **Standard:** `SPEC#textDocument_didOpen` — open and close notifications must be balanced. `[INFERENCE]` wording not re-fetched.
- **Fix:** before each `server.openDocument` in `reopen`, re-check that the document is still open (track closed URIs, or keep the pending set in `lostDocuments`, which `closeDocument` already prunes).
- **Confidence:** medium. `[INFERENCE]` it assumes `CodeFileDocument.content` survives close. The existing test `explicitRestartOfAFailedServerSkipsDocumentsClosedInTheMeantime` shows that skipping closed documents is the intended behaviour.
- **Test:** crash with a long backoff, call `closeDocument(b)`, let the restart run, and expect only `a` in `lspServiceOpens`.

## LSP-07 — P2 — Edits for editor-open documents the client does not track go straight to disk
- **Where:** `Service/LSPService+ClientRequests.swift:162-164`; `Service/LSPWorkspaceEditing.swift:218-221, 238-248`.
- **Quote:**
  ```swift
  guard let document, let storage = document.content else { return false }
  …
  try Self.editFile(uri: uri, edits: edits)
  ```
- **Sequence:**
  1. `a.ts` is open with unsaved edits but untracked (LSP-05).
  2. A rename from `c.ts` returns edits for `a.ts`.
  3. `editOpenDocument` returns `false`, so `editFile` rewrites the file on disk from disk content.
  4. The buffer and the file diverge; the next save overwrites the rename, or the unsaved edits conflict.
  `[INFERENCE]` the same path is hit when the server returns a symlink-resolved URI that differs from `languageServerURI`.
- **Standard:** `SPEC#textDocument_didOpen` — once open, the client's buffer is the source of truth. `[INFERENCE]` wording not re-fetched.
- **Fix:** before `editFile`, look the URL up among all open `CodeFileDocument`s (resolved path) and edit the buffer, or fail the operation.
- **Confidence:** medium.
- **Test:** an applier whose client has no tracked document while a `CodeFileDocument` for the URL is open and dirty; expect the disk file untouched.

## LSP-08 — P2 — Edits typed while the first `didOpen` is in flight are dropped
- **Where:** `LanguageServer+DocumentSync.swift:30-32`; `LSPContentCoordinator.swift:77-80`.
- **Quote:**
  ```swift
  guard let lspRange = editedRange, let documentURI else {
      return
  }
  ```
- **Sequence:** `openDocument` snapshots the text and awaits `textDocumentDidOpen`. A keystroke lands during that await; `documentURI` is still nil, so the edit is not recorded and the server stays one edit behind.
- **Standard:** `SPEC#textDocument_didChange`.
- **Fix:** call `updateIsolatedDocument(document)` before the `await`, in the same turn as the content read.
- **Confidence:** medium. The window is a single send.
- **Test:** a gated fake connection that suspends `didOpen`; edit through the text view; release; expect a `didChange` after the flush.

## LSP-09 — P2 — Position conversion does not clamp `character` to the line
- **Where:** `Features/TextPositions/LSPTextPositionConverter.swift:7-9`; used by `LSPCompletionDelegate.swift:239, 276` and `SelectionRangeCoordinator.swift:107`.
- **Quote:**
  ```swift
  let offset = line.range.location + Int(position.character)
  guard offset >= line.range.location, offset <= textView.textStorage.length else { return nil }
  ```
- **Sequence:** the text is `"ab\ncdef"`. A completion `textEdit` ending at `(line 0, character 5)` resolves to offset 5, inside line 1, so the edit deletes the newline and `cd`. With `character 100` the result is `nil` and the completion silently does nothing.
- **Standard:** `SPEC#position` — a character beyond the line length falls back to the line length. `[INFERENCE]` wording not re-fetched. `LSPTextEditApplier.LineTable.offset` already clamps.
- **Fix:** `min(character, line content length excluding the terminator)`.
- **Confidence:** high. No test references `LSPTextPositionConverter.offset`.
- **Test:** a hosted text view with `"ab\ncdef"`; expect `offset(of: Position(line: 0, character: 5)) == 2`.

## LSP-10 — P2 — Server file operations run unconfined and delete permanently
- **Where:** `Service/LSPWorkspaceEditing.swift:222-227` and `deleteFile` at `289` onward; `LanguageServer/LanguageServer+InitParams.swift:115`.
- **Quote:**
  ```swift
  case let .deleteFile(uri, recursive, ignoreIfNotExists):
      try Self.deleteFile(uri: uri, recursive: recursive, ignoreIfNotExists: ignoreIfNotExists)
  ```
- **Sequence:** a server sends `workspace/applyEdit` with a recursive `delete` of a `file:///` URI outside the workspace root. `LSPFileURI.fileURL` accepts it and the tree is removed with no confirmation, no Trash and no undo.
- **Standard:** `SPEC#workspaceEditClientCapabilities` — resource operations are declared through `resourceOperations`; this client sends `workspaceEdit: nil` yet executes them. Workspace confinement itself is not documented in official sources.
- **Fix:** reject create, rename and delete, since they are not advertised; or confine them to `rootPath` and move deletions to the Trash.
- **Confidence:** medium. The executor code up to line 300 was read; the tail of `deleteFile` was not. It needs a misbehaving or compromised server, which LSP-01 makes plausible.
- **Test:** an executor given a `deleteFile` outside a temp root; expect `applied == false` and the file intact.

## LSP-11 — P2 — `documentOperations` grows for every URI ever opened
- **Where:** `Service/LSPService+Documents.swift:77-78`; declaration at `Service/LSPService.swift:146`.
- **Quote:**
  ```swift
  let previous = documentOperations[uri]
  documentOperations[uri] = Task {
      await previous?.value
      await operation()
  ```
- **Sequence:** every `openDocument` or `closeDocument` stores a task under its URI. Nothing removes it (the only other use is the read in `waitForDocumentOperations`), including `closeWorkspace` and `stopAllServers`. The shared service keeps one finished task per file for the app's lifetime.
- **Standard:** not documented in official sources; a resource-lifetime defect.
- **Fix:** when a task finishes, remove the entry if it is still the stored one (token or identity comparison).
- **Confidence:** high.
- **Test:** open and close N distinct documents, wait, and expect `documentOperations.isEmpty`.

## Dropped as intentional or speculative
- `InitializationGatedConnection.close()` drops server requests unanswered during shutdown; this looks deliberate.
- `languageConfigs` keeps a custom server path after the setting is cleared; no external standard applies.
- `LSPCache` eviction is O(n); performance only.
- The `showMessageRequest` modal on the main actor is by design.
