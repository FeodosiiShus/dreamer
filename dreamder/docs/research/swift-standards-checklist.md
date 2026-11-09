# Production-readiness checklist: Swift 6 macOS editor (subprocesses, UTF-16 protocols, documents, SwiftUI over AppKit)

Scope: 40 rules. Every quote below was read from the cited official source during this run (swift-evolution and swift-book/swift-testing/swift-migration-guide sources on github.com/swiftlang, developer.apple.com documentation, the LSP 3.17 specification, macOS man pages). Where a Apple page renders inline code that my extraction dropped, the quote is cut at that point. "Repo evidence" lines are things I observed in `dreamder/Dreamder/` (read-only counts or file reads); everything else about the repo is not claimed. `[INFERENCE]` marks conclusions not stated by a source.

Source-bases used:
- TSPL = https://docs.swift.org/swift-book/documentation/the-swift-programming-language/ (text read from github.com/swiftlang/swift-book `TSPL.docc/LanguageGuide/*.md`)
- SE = https://github.com/swiftlang/swift-evolution/blob/main/proposals/
- ST = https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/
- AD = https://developer.apple.com/documentation/

---

## A. Isolation and data races

**1. Compile every target in Swift 6 mode with strict concurrency and treat every escape hatch as a reviewed exception.**
- Why: data races are nondeterministic crashes and corrupted documents that only show up on user machines.
- Detect: `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency import`, `SWIFT_STRICT_CONCURRENCY` below `complete`, `swiftLanguageMode` below 6.
- Source: https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/DataRaceSafety.md — "Using tools such as locks and queues, the prevention of data races was entirely up to the programmer. This is notoriously difficult not just to do correctly, but also to keep correct over time."
- Repo evidence: AGENTS.md states one `@unchecked Sendable` left (`ProcessExecution.UnsafeSendable`); my count of `@unchecked Sendable` in `Dreamder/` is 1 and `nonisolated(unsafe)` is 0.

**2. Every global or static mutable variable is global-actor isolated, or it is immutable and `Sendable` (use `Mutex` for the synchronous-lock case).**
- Why: a bare `static var` cache shared between the LSP, git and UI layers is the classic silent data race.
- Detect: `static var`, top-level `var`, `static let` of non-Sendable class type; `Mutex` is the sanctioned lock (SE-0433).
- Source: SE `0412-strict-concurrency-for-global-variables.md` — "Global variables that are immutable and `Sendable` can be safely accessed from any context, and otherwise, isolation is required."

**3. Conform a type to `Sendable` only when its public API is safe across domains; never use `@unchecked` to silence a diagnostic.**
- Why: `@unchecked Sendable` on a type holding `Process`, `FileHandle` or `NSTextStorage` moves the race from compile time to production.
- Detect: `grep -rn "@unchecked Sendable"`; each hit needs a lock (`Mutex`) or an immutable representation around every stored property.
- Source: SE `0302-concurrent-value-and-concurrent-closures.md` — "It is a good idea for types to conform to the `Sendable` protocol when they are designed so all of their public API is safe to use across concurrency domains." and "note: add '@unchecked' if you know what you're doing."

**4. Do not assume actor state survives an `await`; re-validate after every suspension point.**
- Why: actor methods are reentrant, so a "check, await, act" sequence (cache lookup, request de-duplication, server-state machine) interleaves with other callers.
- Detect: inside `actor` / `@MainActor` types, any `guard`/`if` on stored state followed by `await` and a later use of the same state without re-checking; dictionaries of in-flight work keyed before an `await` and removed after.
- Source: SE `0306-actors.md` — "actor-isolated state can change across an `await` when an interleaved task mutates that state, meaning that developers must be sure not to break invariants across an await."

**5. Under default `@MainActor` isolation, put every blocking or heavy function (git, process waits, directory walks, indexing, parsing) behind `@concurrent` or an actor.**
- Why: nonisolated async functions now run on the caller's actor, so unmarked heavy work silently stalls the UI thread.
- Detect: `FileManager.default.enumerator`, `contentsOfDirectory`, `Data(contentsOf:)`, `String(contentsOf:)`, `waitUntilExit`, `waitid`, JSON decoding of large payloads inside non-`@concurrent`, non-`nonisolated` async or sync functions in the app target; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` plus `nonisolated(nonsending)` upcoming feature.
- Source: SE `0461-async-function-isolation.md` — "This proposal changes the behavior of nonisolated async functions to run on the caller's actor by default, and introduces an explicit way to state that an async function always switches off of an actor to run." and SE `0466-control-default-actor-isolation.md` — "This proposal introduces a new compiler setting for inferring `@MainActor` isolation by default within the module to mitigate false-positive data-race safety errors in sequential code."
- Repo evidence: 17 `String(contentsOf:)` call sites in 14 files (not individually classified).

**6. Touch AppKit/SwiftUI objects only on the main actor; hop explicitly from callbacks, and use `MainActor.assumeIsolated` only where the API is documented to run on main.**
- Why: AppKit is not thread-safe for event-path objects, and `assumeIsolated` traps the whole process if the guess is wrong.
- Detect: closures passed to `DispatchQueue.global`, `FileHandle.readabilityHandler`, `Process.terminationHandler`, FSEvents, XPC, `NotificationCenter` with `queue: nil`, `Task.detached` that reference `NSView`/`NSWindow`/`NSTextView`/models; every `assumeIsolated` call (check the call site's queue); `nonisolated override` of NSDocument/NSView methods.
- Source: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html — "The main thread of the application is responsible for handling events. Although the Application Kit continues to work if other threads are involved in the event path, operations can occur out of sequence." ; AD `swift/mainactor` (`assumeIsolated`) — "Assume that the current task is executing on the main actor’s serial executor, or stop program execution."
- Repo evidence: 61 `assumeIsolated` occurrences. `CodeFileDocument.read(from:ofType:)` is `nonisolated` and calls `MainActor.assumeIsolated` (`CodeFileDocument.swift:183-189`); NSDocument reads on the main thread by default, so this is correct unless `canConcurrentlyReadDocuments(ofType:)` is overridden (not found in `Dreamder/`) [INFERENCE].

## B. Task lifetime, cancellation, continuations, time

**7. Every unstructured `Task` has an owner that cancels it (stored handle cancelled on teardown, or a structured/`.task` scope).**
- Why: a `Task` runs regardless of whether anyone holds it, so orphaned loops keep mutating models and spawning processes after the window closed.
- Detect: `Task {` / `Task(priority:)` whose result is not assigned to a stored property, `onAppear { Task { … } }`, `for await` loops inside unstored tasks, tasks created in `init`.
- Source: TSPL Concurrency — "an *unstructured task* doesn't have a parent task. You have complete flexibility to manage unstructured tasks in whatever way your program needs, but you're also completely responsible for their correctness." ; AD `swift/task` — "A task runs regardless of whether you keep a reference to it."
- Repo evidence: 295 `Task {` sites in 149 files (not classified individually); `Task.detached` count is 0.

**8. Long-running task bodies check cancellation, and cancellation is never converted into "continue".**
- Why: cancellation is cooperative; a loop that never checks keeps burning CPU, and `try? await Task.sleep` turns cancel into a tight loop.
- Detect: `try? await Task.sleep` (and `try? await` on any cancellable call) inside `while`/`repeat` loops without `Task.isCancelled`/`checkCancellation()` right after; `while true`, `for await` bodies without a cancellation exit; process readers that ignore cancellation.
- Source: SE `0304-structured-concurrency.md` — "cancellation has no effect at all unless something checks for cancellation." ; TSPL Concurrency — "Swift concurrency uses a cooperative cancellation model."
- Repo evidence: 41 `try? await Task.sleep` sites. The one inspected (`Settings.swift:64-66`) is followed by `guard !Task.isCancelled`; the other 40 were not individually checked.

**9. Bridge cancellable external work (child process, LSP request, URLSession) with `withTaskCancellationHandler`, and keep the handler's state thread-safe.**
- Why: otherwise cancelling the Swift task leaves the child, request or pipe alive and the awaiting task suspended.
- Detect: `withCheckedContinuation`/`withCheckedThrowingContinuation` wrapping a callback or `Process` without a surrounding `withTaskCancellationHandler`; handler closures mutating shared non-atomic variables.
- Source: TSPL Concurrency — "Because the task is still running when the cancellation handler starts, avoid sharing state between the task and its cancellation handler, which could create a race condition." ; AD `swift/withtaskcancellationhandler(operation:oncancel:isolation:)` — "If the task is canceled, this closure is called at most once; otherwise, it isn’t called."
- Repo evidence: 11 checked-continuation sites in 10 files versus 3 `withTaskCancellationHandler` sites in 3 files.

**10. Resume every continuation exactly once on every path, including process crash, EOF, timeout and cancellation; use the checked variants.**
- Why: a double resume traps; a missing resume leaks a suspended task forever (hung "Formatting…" spinner, stuck LSP request).
- Detect: `withUnsafe*Continuation` (ban); stored `CheckedContinuation` values in dictionaries (pending-request tables) without a drain path on server exit; `resume` inside closures that can be called twice (readabilityHandler + terminationHandler); early `return` between the closure start and the resume.
- Source: SE `0300-continuation.md` — "exactly one `resume` method must be called *exactly-once* on every execution path through the program." and "`CheckedContinuation` will also log a warning if the continuation is discarded without ever resuming the task, which leaves the task stuck in its suspended state, leaking any resources it holds."

**11. Use `Task.sleep(for:clock:)` with an injectable clock; use `ContinuousClock`/`SuspendingClock` deliberately, never `Date()` subtraction or `Thread.sleep`.**
- Why: wall-clock differences jump on clock changes and sleep-wake, `Thread.sleep` blocks a cooperative thread, and a fixed real clock makes tests slow and flaky.
- Detect: `Date()` used for elapsed time, `Thread.sleep`, `usleep`, `DispatchQueue.main.asyncAfter` for debounces, `Task.sleep(nanoseconds:)`.
- Source: SE `0374-clock-sleep-for.md` — "If the task is cancelled before the time ends, this function throws `CancellationError`." and "This function doesn't block the underlying thread." ; SE `0329-clock-instant-duration.md` — "When instants are for local processing only and need to be high resolution without the encumbrance of suspension while the machine is asleep, `ContinuousClock` is the tool for the job."
- Repo evidence: 20 `Date()` sites in 14 files (not classified); `Task.sleep(nanoseconds:)` count is 0; 7 `Task.sleep(for:…clock:)` sites.

## C. Errors

**12. Use typed throws only for closed, exhaustively handled error sets (a parser, a codec, a protocol decoder); keep untyped `throws` as the default.**
- Why: typed throws over-constrains evolving APIs, but gives exhaustive handling and removes `any Error` boxing where the failure set is fixed.
- Detect: `throws(` on public/protocol surfaces whose error set will grow; conversely `catch let e as X` followed by a generic `catch` on a module-internal API that could be typed.
- Source: SE `0413-typed-throws.md` — "Even with the introduction of typed throws into Swift, the existing (untyped) `throws` remains the better default error-handling mechanism for most Swift code."

**13. Never use `try?`, `catch {}` or a default value on a path that reads or writes user data (documents, settings, workspace state, session restore); surface the error and keep the original bytes.**
- Why: a swallowed decode or write error turns a recoverable problem into silent data loss (corrupt `settings.json` replaced by defaults on the next save; failed save reported as success).
- Detect: regex `try\?[^\n]*(write|removeItem|moveItem|copyItem|replaceItem|trashItem|createDirectory|save)`, `try? JSONDecoder().decode`, `try? Data(contentsOf:`, `catch\s*\{\s*\}`, `?? .init()` after a failed load.
- Source: TSPL Error Handling — "You use `try?` to handle an error by converting it to an optional value. If an error is thrown while evaluating the `try?` expression, the value of the expression is `nil`."
- Repo evidence (observed): `Settings.swift:74` `try? savePreferences(preferences)` drops a failed save; `Settings.swift:110-114` returns `.init()` when `settings.json` fails to decode, so the next debounce flush overwrites the unreadable file with defaults. 25 other `try?` sites match the regex above (not individually reviewed); 0 `catch {}`.

## D. ARC, observers, timers

**14. A closure stored on `self` (or on a long-lived object owned by `self`) captures `self` weakly or not at all.**
- Why: closure-property cycles keep documents, windows and their text storage alive for the whole session.
- Detect: stored closure properties (`var onX: () -> Void`, `lazy var … = { … }`) whose body mentions `self`; `Task { … self … }` stored on `self`; Combine `sink` stored in `self` that captures `self` strongly; note `unowned` is banned by this repo's crash guard.
- Source: TSPL Automatic Reference Counting — "This strong reference cycle occurs because closures, like classes, are *reference types*. When you assign a closure to a property, you are assigning a *reference* to that closure."

**15. Every observer token, timer and subscription is stored and removed or invalidated at teardown.**
- Why: the notification center and run loop hold the block strongly until you unregister, so leaks outlive the owner and fire against dead state.
- Detect: `addObserver(forName:` whose returned token is not stored; `Timer.scheduledTimer`/`Timer.publish`/`DispatchSource.makeTimerSource` without `invalidate`/`cancel`; `NSEvent.addLocalMonitorForEvents` without `removeMonitor`; `.sink` without `store(in:)`.
- Source: AD `foundation/notificationcenter/addobserver(forname:object:queue:using:)` — "The notification center strongly holds the copied block until you remove the observer registration." ; AD `foundation/timer/scheduledtimer(withtimeinterval:repeats:block:)` — "the timer will repeatedly reschedule itself until invalidated."
- Repo evidence: 3 `addObserver(forName` sites; 0 `Timer.scheduledTimer`; 9 Combine `.sink {` sites.

**16. A long-lived task stored on its owner (an `Observations`/`for await` loop) must not capture the owner strongly.**
- Why: `deinit` (including `isolated deinit { task.cancel() }`) can never run if the task that would be cancelled keeps `self` alive.
- Detect: `Task { for await … in Observations { … self … } }` and `Task { while … { … self.x … } }` stored in `self.*Task` without `[weak self]`; unit test that deallocates the model and asserts a weak reference becomes nil.
- Source: TSPL Automatic Reference Counting — "two strong references are keeping each other alive" ; SE `0371-isolated-synchronous-deinit.md` — "`Task { await self.click(moreClicks) } // ❌ This WILL keep `self` alive after the `deinit`!`"
- Repo evidence: 209 `[weak self` sites; 47 `isolated deinit`; 15 `Observations {` sites in 11 files (capture lists not individually reviewed).

**17. Do not rely on `deinit` (isolated or not) to release descriptors, child processes or ptys; close them on an explicit lifecycle event.**
- Why: isolated deinit may be deferred, so a descriptor or shell can outlive the window and exhaust the fd or process limit.
- Detect: `isolated deinit` bodies that `close()`, `kill`, `terminate`, `cancel` processes; `FileHandle(fileDescriptor:closeOnDealloc:)`; pty masters never closed after session end; check `lsof -p <pid>` growth after opening/closing 50 terminals.
- Source: SE `0371-isolated-synchronous-deinit.md` — "APIs which require quick and predictable resource cleanup, such as scarce resources such as e.g. file descriptors or connections, should not be managed using isolated deinitializers, as the exact timing of when the resource would be released is non-deterministic".
- Repo evidence: AGENTS.md "Known leftovers" states each terminal session keeps one pty descriptor until SwiftTerm is fixed.

## E. Observation and SwiftUI

**18. Treat `Observations` as a coalescing stream of consistent states, never as an event log.**
- Why: values are transactional (first `willSet` to the next suspension), so intermediate mutations are skipped and side effects that need every change (undo steps, counters, log lines) are lost.
- Detect: `Observations { … }` loops whose body performs one side effect per value (send to LSP, append history, play sound); use `AsyncStream` or direct method calls for events; `@Observable` properties for caches/tasks/subscriptions missing `@ObservationIgnored`.
- Source: SE `0475-observed.md` — "the implementation must be transactional upon that suspension"; AD `observation/observations` — "tracks the transactional changes of … types … starting from the willSet of the first mutation to the next suspension point".
- Repo evidence: 15 `Observations {` sites in 11 files.

**19. SwiftUI `@State` is private and owns exactly one source of truth; never assign it in `init` or mirror it from a parent.**
- Why: memberwise-initialised or re-assigned `@State` fights SwiftUI's storage and produces stale or duplicated models.
- Detect: `@State var` without `private`; `_x = State(initialValue:` and `self.x = …` of a `@State` property inside `init`; model objects created in `body`.
- Source: AD `swiftui/state` — "Use state as the single source of truth for a given value type that you store in a view hierarchy." and "Declare state as private to prevent setting it in a memberwise initializer, which can conflict with the storage management that SwiftUI provides".

**20. Use `.task(id:)` for view-scoped async work; key it by the input, and let cancellation end the work.**
- Why: `.task` is cancelled when the view disappears and restarted when the id changes; `Task {}` in `onAppear` or `onChange` is neither.
- Detect: `.onAppear { Task {`, `.onChange(of:) { Task {`, `.task { … try? … }` bodies that swallow `CancellationError` and continue, ids that are not `Equatable` value inputs.
- Source: AD `swiftui/view/task(id:name:priority:file:line:_:)` — "SwiftUI can automatically cancel the task after the view disappears before the action completes. If the id value changes, SwiftUI cancels and restarts the task."
- Repo evidence: 7 `.task(id:` sites.

## F. Documents and persistence

**21. Override `NSDocument.autosavesInPlace` and `autosavingFileType` as `nonisolated`, backed by thread-safe state.**
- Why: AppKit calls them off the main thread, so a main-actor read crashes or races.
- Detect: `override class var autosavesInPlace` / `override var autosavingFileType` that are main-actor isolated or read `@Observable` state.
- Source: AD `appkit/nsdocument/autosavesinplace` — "AppKit invokes this method at a variety of times, and not always on the main thread."
- Repo evidence: compliant: `CodeFileDocument.swift:129-135` are `nonisolated` and read a `Mutex`.

**22. Override `canAsynchronouslyWrite(to:ofType:for:)` to return true only after snapshotting main-actor state on the main thread; otherwise saves block the UI.**
- Why: large files saved on the main thread are a hang source; a half-done snapshot is a corruption source.
- Detect: `data(ofType:)`/`write(to:ofType:)` overrides that read UI/models directly; absence of a `canAsynchronouslyWrite` override.
- Source: AD `appkit/nsdocument/canasynchronouslywrite(to:oftype:for:)` — "You are strongly encouraged to override it and make it return true, after making sure your overrides of document writing methods can be safely invoked on a non-main thread" (my extraction drops the word `true` in code font; quote cut accordingly).
- Repo evidence: 0 `canAsynchronouslyWrite`; `CodeFileDocument.data(ofType:)` runs on the main actor (`CodeFileDocument.swift:168-177`), which is correct for the default synchronous path.

**23. Document saves go through `NSDocument`'s safe-save path; call the completion handler on the main thread and report failures to the user.**
- Why: `writeSafely` protects the existing file from crash/power loss mid-write; custom truncate-and-write destroys it.
- Detect: overrides of `write(to:ofType:forSaveOperation:originalContentsURL:)` that skip `super`; `FileHandle(forWritingTo:)` + `truncate` on document URLs; `save(to:ofType:for:completionHandler:)` completion invoked on a background thread.
- Source: AD `appkit/nsdocument/writesafely(to:oftype:for:)` — "This method is responsible for doing document writing in a way that minimizes the danger of leaving the disk to which writing is being done in an inconsistent state in the event of an app crash, system crash, hardware failure, power outage, and so on." ; AD `appkit/nsdocument/save(to:oftype:for:completionhandler:)` — "The completion handler must be invoked on the main thread."

**24. Non-document files (settings, themes, workspace state, session restore, refactor output) are written atomically or via `replaceItemAt`.**
- Why: a crash or full disk mid-write leaves a truncated JSON that the next launch cannot parse (see rule 13).
- Detect: `.write(to:` without `.atomic`/`atomically: true`; `FileManager.createFile` over an existing file; `removeItem` followed by `write`.
- Source: AD `foundation/nsdata/writingoptions/atomic` — "An option to write data to an auxiliary file first and then replace the original file with the auxiliary file when the write completes." ; AD `foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:)` — "Replaces the contents of the item at the specified URL in a manner that ensures no data loss occurs."
- Repo evidence: `Settings.swift:124` uses `.atomic`. A regex for `.write(to:` calls without `atomic` on the same line matched 22 sites (e.g. `ThemeModel+CRUD.swift:249`, `IgnorePatternModel.swift:183,266`, `RegistryManager+HandleRegistryFile.swift:70`); some may be multi-line `.atomic` calls or `String.write(to:atomically:)`, not individually reviewed.

**25. Writes to files that other processes or file presenters touch (workspace files edited by git, formatters, LSP edits) go through `NSFileCoordinator` or `NSDocument`.**
- Why: coordination lets presenters (other windows, iCloud, Time Machine) finish integrity work before your change lands.
- Detect: raw `Data.write` / `FileManager.moveItem` / `removeItem` on workspace files outside `NSDocument`; zero uses of `NSFileCoordinator` or `NSFilePresenter` in an editor that renames/refactors files.
- Source: AD `foundation/nsfilecoordinator` — "coordinates the reading and writing of files and directories among multiple processes and objects in the same process."
- Repo evidence: 0 `NSFileCoordinator` uses in `Dreamder/`. Whether it is required for local non-iCloud workspaces is [INFERENCE]; the page states the purpose, not a mandatory scope.

**26. If the app is (or will be) sandboxed, balance every `startAccessingSecurityScopedResource` with `stopAccessing…` and handle stale bookmarks.**
- Why: leaked scopes eventually stop the app from adding any new location to its sandbox until relaunch.
- Detect: `startAccessingSecurityScopedResource()` without a `defer { stop… }`; `URL(resolvingBookmarkData:)` ignoring `bookmarkDataIsStale`; bookmark resolution on the main thread for lists.
- Source: AD `foundation/url/startaccessingsecurityscopedresource()` — "If you fail to relinquish your access to file-system resources when you no longer need them, your app leaks kernel resources."
- Repo evidence: 0 `startAccessingSecurityScopedResource` in `Dreamder/`; AGENTS.md says the WelcomeWindow package resolves bookmarks over XPC on the main thread (3 s for 100 entries).

## G. Subprocesses and pseudo-terminals

**27. Drain stdout and stderr concurrently while the child runs, and only then read the termination status.**
- Why: a pipe buffer is finite, so a chatty child (git log, LSP stderr) blocks forever if nobody reads it, and a wait-before-read deadlocks.
- Detect: `waitUntilExit` or a `terminationHandler` continuation before `readDataToEndOfFile`/`availableData`; one `Pipe` read while the other is not; `readabilityHandler` never set to `nil` after EOF; reading `availableData` in a loop on a cooperative thread.
- Source: AD `foundation/pipe` — "The data that passes through the pipe is buffered; the size of the buffer is determined by the underlying operating system." ; AD `foundation/process/standardoutput` — "launching the receiver automatically closes the write end of the pipe in the current task. Don’t create a handle for the pipe and pass that as the argument, or the write end of the pipe won’t be closed automatically." ; AD `foundation/filehandle/readabilityhandler` — "Your block is submitted to the file handle’s dispatch queue when there is data to read."
- Repo evidence: 5 `readabilityHandler` sites in 1 file, 3 `terminationHandler` sites in 2 files.

**28. Never block a thread waiting for a child on the main actor or a cooperative-pool thread.**
- Why: `waitUntilExit` spins the current run loop, so on main it re-enters event handling, and on the cooperative pool it consumes a thread.
- Detect: `waitUntilExit()`, `waitpid`, `waitid`, `Process.run()` followed by a synchronous read outside a `@concurrent`/dedicated-thread function.
- Source: AD `foundation/process/waituntilexit()` — "Then it polls the current run loop using NSDefaultRunLoopMode until the task completes."
- Repo evidence: 0 `waitUntilExit` in `Dreamder/`; AGENTS.md rule 10 requires `@concurrent` for `waitid`.

**29. Install `terminationHandler` before `run()`, resume exactly once, and handle the `run()` throw path.**
- Why: a process that exits before the handler is set, or a `run()` that throws, leaves the awaiting task suspended forever.
- Detect: `try process.run()` followed by `terminationHandler = …`; continuation resumed in both the handler and a catch block; `process.terminationStatus` read before `isRunning == false`; `terminationReason` ignored (signals).
- Source: AD `foundation/process/terminationhandler` — "A completion block the system invokes when the task completes. The system passes the task object to the block to allow access to the task parameters, for example to determine if the task completed successfully." and (same page) "This block isn’t guaranteed to be fully executed prior to … returning." (extraction drops the code-font symbol).

**30. Children inherit only the descriptors and environment you intend: close-on-exec everywhere, `POSIX_SPAWN_CLOEXEC_DEFAULT` (or an equivalent) when spawning directly, and a sanitized environment.**
- Why: leaked pty masters, pipes and sockets keep EOF from arriving, keep files locked, and leak secrets from the parent environment into every language server and shell.
- Detect: `pipe(`/`open(`/`socket(` without `O_CLOEXEC`/`FD_CLOEXEC`; `posix_spawn`/`forkpty`/`fork` use without `POSIX_SPAWN_CLOEXEC_DEFAULT` or an explicit close loop; `Process` with `environment == nil` (inherits everything); fake servers using `exec cat` that keep stdout open.
- Source: macOS man page `posix_spawnattr_setflags(3)` (read locally with `man posix_spawnattr_setflags`) — "POSIX_SPAWN_CLOEXEC_DEFAULT  Apple Extension: If this bit is set, then only file descriptors explicitly created by the file_actions argument are available in the spawned process; all of the other file descriptors are automatically closed in the" (line wraps in the page); man page `pipe(2)` — "O_CLOEXEC  Set the close-on-exec (FD_CLOEXEC) flag on both new descriptors."; AD `foundation/process` — "inheriting its environment from the process that launches it."
- Repo evidence: 0 `posix_spawn`/`forkpty`/`openpty` in `Dreamder/` (terminal spawning is in the SwiftTerm package); AGENTS.md rule 10 requires a sanitized `ProcessEnvironment`.

## H. Text positions

**31. Keep one position type per layer and convert at the boundary: `String.Index` and `Character` offsets are not UTF-16 offsets or `NSRange`.**
- Why: a single emoji, combining accent or CRLF shifts every later offset, so edits and LSP ranges land in the wrong place or split surrogate pairs.
- Detect: `NSRange(location: n, length: …)` built from `.count`/`Array(text)`; `text.index(startIndex, offsetBy: nsRange.location)`; `utf16.count` mixed with `count`; `Range(nsRange, in: string)` result force-unwrapped or ignored; integer subscripting helpers on `String`; `NSString.length` compared to `String.count`.
- Source: TSPL Strings and Characters — "For this reason, Swift strings can't be indexed by integer values." and "The length of an `NSString` is based on the number of 16-bit code units within the string's UTF-16 representation and not the number of Unicode extended grapheme clusters within the string."
- Repo evidence: 168 `NSRange(` sites in 81 files, 217 `.utf16` sites in 64 files (not individually reviewed).

**32. Speak UTF-16 unless `positionEncoding` was negotiated: convert editor offsets to LSP `Position` as UTF-16 code units, and never advertise UTF-8/UTF-32 without converting.**
- Why: servers and clients that disagree on encoding put diagnostics, rename edits and semantic tokens at wrong columns for any non-ASCII line.
- Detect: `positionEncodings` in client capabilities and `positionEncoding` in the initialize result (absent → UTF-16); `Position(character: line.count)` or byte offsets from tree-sitter used directly; lines with astral characters in fixtures.
- Source: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/ — "Character offsets count UTF-16 code units." and "If the string value utf-16 is missing from the client’s capability general.positionEncodings servers can safely assume that the client supports UTF-16."
- Repo evidence: 0 `positionEncoding` hits in `Dreamder/`, so UTF-16 is implicitly assumed; correctness then depends on every conversion site (rule 31).

**33. Apply LSP `TextEdit` arrays against the document version they were computed on, all at once, with non-overlapping ranges.**
- Why: applying edits one by one to the mutated text, or after more typing, corrupts the buffer; formatting and rename are the common victims.
- Detect: loops that apply edits sequentially in server order and re-read the text; no version check between request and apply; `workspace/applyEdit` handled without verifying `textDocument.version`.
- Source: LSP 3.17 specification — "All text edits ranges refer to positions in the document they are computed on." and "Text edits ranges must never overlap".
- Repo evidence: AGENTS.md states requests are cached by position and document version and that completion edit planning follows characters typed since the request; I did not verify the apply path.

## I. Logging and diagnostics

**34. Log with `Logger`; mark paths, URLs, argv, environment, file contents and server messages `.private` (the default for dynamic strings), `.public` only for enums, codes and counts, and log failures at `.error`/`.fault`.**
- Why: a diagnostic bundle from a user must not leak source paths and code, while debug/info messages are not persisted and so are missing when a failure needs investigating.
- Detect: `privacy: .public` on `String`/`URL`/`Error` interpolations; `print(`, `NSLog(`, `os_log(` with `%{public}@`; failures logged at `.debug`/`.info`.
- Source: AD `os/logger` — "When you include an interpolated string or custom object in your message, the system redacts the value of that string or object by default." ; AD `os/generating-log-messages-from-your-code` (log-level table) — "Debug No" … "Info Only when collected with the log tool".
- Repo evidence: 36 `privacy: .public` sites and 12 `print(` sites in `Dreamder/`; not individually reviewed.

**35. Subscribe to MetricKit diagnostics (crashes, hangs, CPU/disk exceptions) and keep dSYMs for every shipped build.**
- Why: the crash guard prevents known traps but not hangs, deadlocks or system-killed launches; without field reports they stay invisible, and without dSYMs they cannot be symbolicated.
- Detect: absence of `MXMetricManager.shared.add(subscriber)`; `DEBUG_INFORMATION_FORMAT` not `dwarf-with-dsym` in Release; dSYM not archived next to each release artifact; main-thread blockers (rule 5/28) with no hang telemetry.
- Source: AD `metrickit/mxmetricmanager` — "The system delivers metric reports at most once per day per metric source, and diagnostic reports immediately in iOS 15 and later and macOS 12 and later." ; AD `xcode/understanding-hangs-in-your-app` — "A hang is almost always the result of long-running work on the main thread." ; AD `xcode/building-your-app-to-include-debugging-information` — "Each binary file in an app — the main app executable, frameworks, and app extensions — has its own dSYM file."
- Repo evidence: 0 `MXMetricManager` in `Dreamder/`; CI uploads Release app and dSYM artifacts (AGENTS.md, workflow description).

## J. Signing and distribution

**36. Ship with the Hardened Runtime on, and add only the entitlements the app provably needs.**
- Why: each runtime exception (JIT, unsigned memory, disabling library validation) re-opens injection paths in an app that executes user-installed language servers and shells.
- Detect: `ENABLE_HARDENED_RUNTIME` (must be `YES` in Release), `*.entitlements` containing `com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, `get-task-allow` in Release.
- Source: AD `security/hardened-runtime` — "The Hardened Runtime doesn’t affect the operation of most apps, but it does disallow certain less common capabilities, like just-in-time (JIT) compilation." and "Make sure to use only the entitlements that are absolutely necessary for your app’s functionality."

**37. Notarize every distributed build (Developer ID, Hardened Runtime, secure timestamp, all nested executables signed) and staple the ticket.**
- Why: without notarization Gatekeeper warns on every download, and bundled helpers (language server binaries, `OpenWithDreamder`, frameworks) fail the notary check if any one of them is unsigned or lacks the Hardened Runtime.
- Detect: `CODE_SIGN_IDENTITY = -` (ad-hoc) in the release path; `codesign -dvv --entitlements - <each nested Mach-O>` missing `runtime` flag or timestamp; no `xcrun notarytool submit … --wait` / `xcrun stapler staple` in CI.
- Source: AD `security/notarizing-macos-software-before-distribution` — "Notarize your macOS software to give users more confidence that the Developer ID-signed software you distribute has been checked by Apple for malicious components." and "Enable the Hardened Runtime capability for your app and command line targets".
- Repo evidence: AGENTS.md "Known leftovers": ad-hoc signature, no notarization, Gatekeeper warning on downloads.

## K. Swift Testing

**38. In a shared-process test host, assume every test runs in parallel; put shared global state behind `.serialized` suites or injected stores, and remember `.serialized` does not serialize against unrelated suites.**
- Why: `.serialized` on one suite does not stop other suites from running concurrently, so a global-state test can still race with hundreds of others.
- Detect: tests writing `UserDefaults.standard`, `Settings.shared`, environment variables, current directory, or singleton registries; `@Suite(.serialized)` used as the only protection for a global; `--no-parallel` as a crutch.
- Source: ST `Parallelization.md` — "By default, tests run in parallel with respect to each other." and "This trait doesn't affect the execution of a test relative to its peers or to unrelated tests."
- Repo evidence: AGENTS.md rules 12 and 15 describe a `.uiGate` trait and isolated defaults for this reason.

**39. Give every test that can block a time limit, and size it knowing Swift Testing rounds limits to one-minute granularity.**
- Why: a stalled main thread or child process otherwise hangs the whole CI run until the job timeout, with no failing test to blame.
- Detect: tests awaiting processes, LSP servers, pasteboard, modal APIs or `RunLoop` without `.timeLimit`; limits under a minute that will be rounded; limits set only on tests, not on suite scope work (suite setup is not covered by a per-test limit).
- Source: ST `LimitingExecutionTime.md` — "a granularity of (by default) one minute is applied to tests." and "the task in which it's running is cancelled and the test fails" (source text: "is [cancelled](…) and the test fails with an issue of kind `timeLimitExceeded`").
- Repo evidence: AGENTS.md rule 15 states the 120 s per-test-case limit in the test plan does not wrap suite scopes.

**40. Assert asynchronous events with `confirmation(expectedCount:)`, not with sleeps or polling, and cancel/await your own tasks before the test ends.**
- Why: sleeps make tests slow on loaded CI runners and flaky on fast ones; unawaited tasks leak into other tests in the shared host.
- Detect: `Task.sleep` followed by `#expect`; `RunLoop.main.run`; `DispatchSemaphore.wait` in tests; `Task { … }` in a test with no awaited handle; callbacks asserted after the test function returned.
- Source: ST `testing-asynchronous-code.md` — "In more complex situations you can use ``Confirmation`` to discover whether an expected event happens." and "The test passes if the number of occurrences during the test matches the expected count, and fails otherwise."

---

## Fastest path to production-ready

Ordered by risk reduction per hour of work. Hour figures are my estimates for this code base [INFERENCE]; "audit" items are bounded by the grep counts noted above.

1. **Rule 13 + 24 (about 3 h).** Stop `try?` on persistence paths; make `loadSettings` keep a `settings.json.bak`/surface decode failure instead of overwriting with defaults; atomic writes on the 22 `.write(to:` candidates. Prevents silent user-data loss, the highest-consequence failure.
2. **Rule 34 (about 1.5 h).** Review the 36 `privacy: .public` and 12 `print(` sites; log failures at `.error`. Cheap, removes a privacy liability before any user shares a log.
3. **Rule 10 + 9 + 29 (about 4 h).** Audit the 11 checked-continuation sites for exactly-once and a drain path on process/server exit; add `withTaskCancellationHandler` where cancellation should kill the child. Removes hangs and leaked servers.
4. **Rule 27 + 30 (about 3 h).** Verify stdout and stderr are drained concurrently in `ProcessRunner`, and that spawned children do not inherit stray descriptors (pty masters, pipes). Prevents deadlocks and fd exhaustion; the known pty leak is the first item.
5. **Rule 8 + 7 + 16 (about 4 h).** Review the 41 `try? await Task.sleep` and `Observations`/stored tasks for cancellation exit and weak capture; add a deallocation test for the main models. Fixes CPU burn and leaks.
6. **Rule 37 + 36 (about 6–10 h, mostly one-time CI work).** Developer ID signing, Hardened Runtime on every nested executable, notarytool + staple. Largest distribution risk, but needs an Apple Developer account decision.
7. **Rule 35 (about 2 h).** Register an `MXMetricManager` subscriber and persist payloads for support; archive dSYMs with release artifacts. Gives visibility into hangs the crash guard cannot see.
8. **Rule 31 + 32 + 33 (about 6 h).** Single boundary type for UTF-16/`NSRange`/LSP positions, round-trip tests with emoji, combining marks and CRLF, and a version check before applying server edits. High impact on correctness, but a broad review (168 `NSRange(` and 217 `.utf16` sites).
9. **Rule 38 + 39 + 40 (about 3 h).** Keep global-state tests out of the shared host, ensure every blocking test has a time limit, replace sleeps by confirmations. Protects CI signal.
10. **Rule 5 + 6 + 28 (about 4 h).** Audit the 61 `assumeIsolated` sites and heavy synchronous work under default `@MainActor` isolation. Removes main-thread hangs and process-killing traps.
11. **Rule 22 + 23 + 25 + 26 (about 5 h).** Decide asynchronous document writing and file coordination policy; make bookmark handling balanced if the app is ever sandboxed. Lower urgency: current NSDocument overrides already follow rule 21.
12. **Rules 1–4, 12, 14, 15, 17–20 (about 1 h each, as part of normal review).** Already largely enforced by Swift 6 mode, the crash guard and repo conventions (AGENTS.md rules 2, 8, 9); keep them as review checks.
