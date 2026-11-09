## Summary

Seven findings. Nothing was built or run; every claim is from reading code, and browser or shell behaviour is marked `[INFERENCE]`.

1. **BUG-01 (P0, data loss):** one wrong-typed key in `settings.json` resets every setting, and the next change overwrites the file with defaults.
2. **BUG-02 (P0, security, headless only):** automation hooks ship in every build, accept distributed notifications from any local process, and the gate can be persisted in user defaults.
3. **BUG-03 (P1):** raw HTML `id="dreamderPreview"` stops the preview from ever updating.
4. **BUG-04 (P1/P2):** `URL.lspURI` sends unencoded paths to language servers.
5. **BUG-05 (P2, crash if reached):** `MarkdownListEnter` traps when the caret is between CR and LF.
6. **BUG-06 (P2):** raw HTML may carry `md-src-pos` and pin preview scroll sync.
7. **BUG-07 (P2):** `escapedDirectory()` leaves `$`, backtick and trailing `\` live in the task `cd` string.

Not covered: the 537-line emphasis toggle beyond its first 300 lines, table actions, `Matching/`, `DreamderUI/`, most of `Notifications/`, and the Finder extension's app-group behaviour. Line numbers for files read without numbering were counted by hand from numbered anchors.

---

# bugs-settings-markdown.md

## BUG-01 — One malformed key resets all settings; next change overwrites the file
- **Severity:** P0 (data loss). **Confidence:** high.
- **Where:** `dreamder/Dreamder/Features/Settings/Models/Settings.swift:110-114` and `:120-126`; `SettingsData.swift:59-66`; `Pages/GeneralSettings/Models/GeneralSettings.swift:75-78`.
- **Quote:**
  ```swift
  guard let json = try? Data(contentsOf: settingsURL),
        let prefs = try? JSONDecoder().decode(SettingsData.self, from: json)
  else {
      return .init()
  }
  ```
  Every level decodes with `try container.decodeIfPresent(...) ?? default`.
- **Failing sequence:**
  1. `settings.json` holds one wrong-typed or unknown-enum value, for example `"defaultTabWidth": "2"`.
  2. `decodeIfPresent` throws, the error propagates through every `try`, and `try?` returns `.init()`: all settings silently default.
  3. The user changes any setting; after the 2 s debounce `savePreferences` writes defaults plus that one change over the file. No backup, no error shown.
  4. A transient read failure of `Data(contentsOf:)` takes the same path.
- **Standard:** Swift's `decodeIfPresent` returns `nil` only for an absent key or null value ([Codable.swift](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Codable.swift), lines 2001-2003). The adjacent `decode` overloads document `DecodingError.typeMismatch` at 1969-1970; applying that to `decodeIfPresent` is `[INFERENCE]`. The file's own comment at `SettingsData.swift:21-23` names the hazard: "Otherwise all settings get overridden."
- **Fix sketch:** decode each section and key leniently (`(try? container.decodeIfPresent(...)) ?? default`). When the file exists but cannot be read or decoded, rename it to `settings.json.invalid-<timestamp>` and report through `NotificationManager` before any save.
- **Test:** in `withTempDir`, write `{"general":{"isAutoSaveOn":false},"textEditing":{"defaultTabWidth":"2"}}` and create `Settings(baseURL:)`. Expect `general.isAutoSaveOn == false` (today `true`). Mutate a setting, call `flushPendingSave()`, and expect the file still to contain `"isAutoSaveOn" : false`.
- **Existing tests:** `DreamderTests/Features/Settings/{SettingsFlushTests,SettingsCoreModelCoverageTests,AutosavePreferenceTests}.swift` only use valid JSON; none asserts reset-on-error.

## BUG-02 — Unauthenticated automation hooks in every build, with a persistable gate
- **Severity:** P0 (security), only while headless mode is on. **Confidence:** high on code, medium on exploitability.
- **Where:** `Features/DreamderAutomation/DreamderAutomation.swift:14-36` and `:140-152`; `DreamderAutomation+Snapshot.swift:9-10`; `DreamderHeadless.swift:10-17`; `AppDelegate.swift:77-78`.
- **Quote:**
  ```swift
  center.addObserver(forName: command.name, object: nil, queue: queue) { note in
      let argument = note.object as? String
      MainActor.assumeIsolated { command.run(argument) }
  }
  ```
  ```swift
  if environment[environmentKey] == "1" { return true }
  return defaults.bool(forKey: argumentKey)
  ```
- **Failing sequence:**
  1. The app runs headless (`make headless` passes `-DreamderHeadless YES`, `Makefile:54`). There is no `#if DEBUG` in the files read, so Release builds include the hooks.
  2. Any local process posts `dev.dreamder.snapshot` with an object path. The app creates that directory and writes PNGs of every editor window plus `windows.txt` with window titles.
  3. `dev.dreamder.action` with an arbitrary string becomes `NSSelectorFromString` sent through the responder chain (for example `terminate:`).
  4. `dev.dreamder.annotate` creates a directory and overwrites `annotate.txt` at any path.
  5. `MergeAutomation.install` (line 35) registers the merge commands; `AGENTS.md` lists `editResult:<text>` and `apply` among them.
  6. The gate reads `UserDefaults.standard`, so a same-user `defaults write dev.dreamder.Dreamder DreamderHeadless -bool YES` makes every later launch invisible, with modals auto-cancelled and hooks active.
- **Standard:** Apple, [DistributedNotificationCenter](https://developer.apple.com/documentation/foundation/distributednotificationcenter): "`NSDistributedNotificationCenter` does not implement a secure communications protocol. When using distributed notifications, your app should treat any data passed in the notification as untrusted."
- **Fix sketch:** compile the hooks under `#if DEBUG` or a dedicated build setting. Resolve the gate from `ProcessInfo.processInfo.arguments` and environment only, never the persistent domain. Require a per-launch nonce in every notification, restrict output paths to an allowed root, and replace arbitrary selectors with an allowlist.
- **Test:**
  - `resolveIsEnabled(environment: [:], defaults: pooled)` with `DreamderHeadless = true` stored in the suite must return `false` after the fix (today `true`).
  - `install(center: NotificationCenter(), enabled: true, queue: nil)` followed by a `dev.dreamder.snapshot` post without the nonce must write nothing.
- **Existing tests:** not opened; `DreamderTests/Features/DreamderAutomation/` exists.

## BUG-03 — Raw HTML `id="dreamderPreview"` permanently disables preview updates
- **Severity:** P1. **Confidence:** medium (browser behaviour not run).
- **Where:** `Features/MarkdownPreview/MarkdownPreviewScripts.swift:9-11`; `MarkdownHTMLSanitizer.swift:143-145`; `MarkdownPreviewWebView.swift:92-97`.
- **Quote:**
  ```js
  if (window.dreamderPreview) {
    return;
  }
  ```
  ```swift
  static let globalAttributes: Set<String> = [
      "id", "class", "title", "lang", "dir", "align", "valign", "width", "height", "role", "md-src-pos"
  ```
- **Failing sequence:**
  1. A Markdown file contains `<div id="dreamderPreview"></div>`; the sanitizer keeps `id`.
  2. `load` puts the body in the initial page. On `didFinish`, `pageScript` reads `window.dreamderPreview`, which resolves to the element `[INFERENCE]`, and returns before installing the API.
  3. Every later `apply` evaluates `window.dreamderPreview.replaceBody(...)`, which is not a function `[INFERENCE]`. The error is dropped by `completionHandler: { _, _ in }`, while `loadedBody = body` is already set.
  4. The preview never updates, never follows scroll, and anchors do nothing. It stays stuck after the element is deleted, because `show` reloads only on a base URL or palette change.
- **Standard:** HTML Standard, [named access on the Window object](https://html.spec.whatwg.org/multipage/nav-history-apis.html#named-access-on-the-window-object): "The `Window` object supports named properties." That `id` values are among them is from the same section but was not in the fetched excerpt.
- **Fix sketch:** install the API unconditionally, or guard on `typeof window.dreamderPreview.replaceBody === "function"`. Better, prefix or strip user-supplied `id` values. Log `evaluateJavaScript` errors instead of discarding them.
- **Test:** in `MarkdownPreviewHostedTests`, load a body containing `<div id="dreamderPreview"></div>`, change the body, then evaluate `document.body.innerHTML` and expect the new content.
- **Existing tests:** `MarkdownHTMLSanitizerTests`, `MarkdownPreviewScriptsCoverageTests` and `MarkdownPreviewScrollScriptTests` do not mention this id.

## BUG-04 — `URL.lspURI` is not percent-encoded
- **Severity:** P1 for files whose path has a space, `#`, `?`, `%` or non-ASCII; otherwise P2. **Confidence:** medium (server reaction is `[INFERENCE]`).
- **Where:** `Utils/Extensions/URL/URL+LSPURI.swift:16`; `URL+absolutePath.swift:11-13`.
- **Quote:**
  ```swift
  var lspURI: String {
      return "file://" + absolutePath
  }
  ```
  ```swift
  absoluteURL.path(percentEncoded: false)
  ```
- **Failing sequence:** open `/proj/a#b.ts` or `/proj/100%25.md`. Every request built from `lspURI` (inlay hints, code actions, formatting, rename, usages, folding; 15+ call sites) sends `file:///proj/a#b.ts`. A conforming parser reads `#b.ts` as a fragment and `%25` as an escape, so the server addresses a different document `[INFERENCE]`.
- **Standard:** the LSP specification's URI section (microsoft.github.io/language-server-protocol) could not be fetched in this run, so this citation is unverified.
- **Fix sketch:** `absoluteURL.standardizedFileURL.absoluteString`, with the same normalisation as `LSPFileURI` so open-document lookup still matches.
- **Test:** `URL(fileURLWithPath: "/tmp/a b#c%.ts").lspURI` must equal `file:///tmp/a%20b%23c%25.ts` and round-trip through `LSPFileURI.fileURL(from:)`.
- **Existing tests:** not checked; the helper has no folder under `DreamderTests/Features/`.

## BUG-05 — `MarkdownListEnter` traps with the caret between CR and LF
- **Severity:** P2 latent; a process crash if reached. **Confidence:** high for the trap, reachability from the UI `[INFERENCE]`.
- **Where:** `Features/Markdown/Typing/MarkdownListEnter.swift:47` and `:128-131`; `MarkdownListStructure.swift:26-28`; caller `MarkdownTypingCoordinator.swift:94-99`.
- **Quote:**
  ```swift
  guard context.caret > 0 else { return nil }
  let before = trimmedStart(context.units[context.lineStart..<context.caret])
  let after = trimmedStart(context.units[context.caret..<context.lineEnd])
  ```
- **Failing sequence:**
  1. `MarkdownListEnter.edit(forEnterIn: "a\r\nb", caret: 2)` passes the guard `caret >= 0, caret <= units.count`.
  2. Line 0 is `start 0, contentEnd 1, end 3`, so `lineEnd` is 1.
  3. `2..<1` is formed before any fence check and traps. `smartEnterAndBackspace` defaults to true.
  4. The coordinator passes `selection.location` unchecked, so any caret placed between `\r` and `\n` in a CRLF Markdown file crashes on Return.
- **Standard:** Swift [Range.swift](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Range.swift) lines 758-762: "Precondition: `minimum <= maximum`", enforced with "Range requires lowerBound <= upperBound". Also `AGENTS.md` rule 9 (crash-free code).
- **Fix sketch:** in `Context.init`, clamp the caret to `min(caret, lines[line].contentEnd)`, or return `nil` when `caret > lineEnd`. Audit the backspace path the same way.
- **Test:** `#expect(MarkdownListEnter.edit(forEnterIn: "a\r\nb", caret: 2) == nil)`. Today this kills the host, so land it with the fix.
- **Existing tests:** `MarkdownListEnterTests.windowsLineEndingsAreKept` (line 227) only puts the caret at the end of the text.

## BUG-06 — Raw HTML may carry `md-src-pos` and pin scroll sync
- **Severity:** P2. **Confidence:** medium.
- **Where:** `Features/MarkdownPreview/MarkdownHTMLSanitizer.swift:143-145`; `MarkdownPreviewScripts.swift:21-33`, `:52-61`, `:63-99`. The sanitizer runs only on user HTML (`MarkdownBlockRenderer.swift:155`, `MarkdownInlineRenderer.swift:178`).
- **Quote:**
  ```js
  var range = rangeOf(child);
  if (range && range.to > last) {
    last = range.to;
  }
  ```
- **Failing sequence:** the document starts with `<div md-src-pos="0..100000000">x</div>`. `documentEndOffset()` returns 1e8. In `sourceOffsetToY`, the first child satisfies `offset <= child.to` for every real offset and has no positioned children, so the fraction is about 0 and the preview stays at the top while the editor scrolls.
- **Standard:** none external; this is an internal invariant that `md-src-pos` is renderer-generated (`AGENTS.md`, MarkdownPreview row).
- **Fix sketch:** remove `"md-src-pos"` from `globalAttributes`.
- **Test:** `MarkdownHTMLSanitizer.sanitize(#"<div md-src-pos="0..9">x</div>"#) == "<div>x</div>"`.
- **Existing tests:** I did not find a test asserting the attribute is kept, but my search pattern was narrow; check `MarkdownHTMLSanitizerTests` before removing it.

## BUG-07 — `escapedDirectory()` is not a safe shell quoting
- **Severity:** P2. **Confidence:** medium (shell semantics `[INFERENCE]`).
- **Where:** `Utils/Extensions/String/String+Escaped.swift:12-14` and `:26-49`; caller `Features/CEWorkspaceSettings/Models/CETask.swift:72`.
- **Quote:**
  ```swift
  /// Escapes the string so it's an always-valid directory
  func escapedDirectory() -> String {
      "\"\(self.escapedQuotes())\""
  }
  ```
- **Failing sequence:**
  - Working directory `/tmp/a$b` yields `cd "/tmp/a$b" && …`; the shell expands `$b` and `cd` targets another directory.
  - Working directory `/tmp/x\` yields `"/tmp/x\"`; the closing quote is escaped and the command line is unterminated.
  - A quote already preceded by `\` is left as is, so a literal backslash is consumed.
- **Standard:** `AGENTS.md` rule 10: "argv arrays, sanitized environment, no shell string interpolation". POSIX double-quote rules were not fetched.
- **Fix sketch:** pass the working directory as the process `currentDirectoryURL` through `ProcessRunner`. If a string is unavoidable, single-quote it and replace `'` with `'\''`.
- **Test:** `"/tmp/a$b".escapedDirectory()` and `#"/tmp/x\"#.escapedDirectory()` run through `/bin/sh -c 'printf %s …'` in a `@concurrent` helper must round-trip the original strings.
- **Existing tests:** not checked.

## Checked, no finding
- **Settings write:** atomic (`.atomic`, `Settings.swift:124`) and flushed in `applicationWillTerminate` (`AppDelegate+Termination.swift:115`).
- **WKWebView:** content JavaScript is off (`MarkdownPreviewWebView.swift:18`); Apple's [allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript) says this covers inline `<script>` and `javascript:` URLs. No message handlers; every non-initial navigation is cancelled.
- **Link policy:** links open only as `http`/`https`/`mailto`, or as files canonically inside the workspace.
- **Sanitizer:** `isSafeURL` decodes entities, strips control characters and rejects any residual `&` before the scheme; `script`/`style` content is dropped; comment, CDATA and PI edge cases are handled; renderer attributes are escaped. Remote `http(s)` images are allowed.
- **Workspace trust:** paths are standardised and symlink-resolved, and prefixes are compared at a `/` boundary. Case-different spellings fail closed (re-prompt); `revoke` has no caller in the app.
- **Keymap:** overrides have no chord type, so equality conflict detection is complete; Remove/Leave/Cancel loses no binding.
