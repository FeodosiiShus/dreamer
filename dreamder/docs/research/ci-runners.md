# GitHub Actions macOS runner research for `dreamder` (as of 2026-11-09)

Scope: official GitHub documentation only (docs.github.com, github.blog/changelog, github.com/actions/*). Local Apple man pages and `xcodebuild -help` are used only for Xcode selection and test flags. `Not documented in official sources` marks every gap. `[INFERENCE]` marks anything derived rather than quoted.

Repo facts read: `.github/workflows/dreamder.yml` (matrix `macos-26`/Xcode 26.6 primary and `xcode-27`/Xcode 27.2, `timeout-minutes: 60`, `fail-fast: false`, one job runs `make build` → `make lint` → `make coverage` → `make smoke` → `make release`), `dreamder/Makefile:1-2` (`XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer` / `export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)`), `dreamder/AGENTS.md` (`make test-sharded` already exists: one `build-for-testing`, then `Scripts/sharded-tests.py` runs one `test-without-building` per shard with `-only-testing` lists).

---

## Q1. Hosted runner labels, status, hardware, Xcode

### 1a. Labels and status

| Label | OS / arch | Status | Official URL | Verbatim quote |
|---|---|---|---|---|
| `macos-26` (also `macos-latest`, `macos-26-xlarge`) | macOS 26.7.2, arm64 | GA | https://github.com/actions/runner-images (README "Available Images") ; https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners | README: "macOS 26 Arm64 … arm64 … `macos-latest`, `macos-26` or `macos-26-xlarge`". Changelog: "`macos-26` – Standard macOS runner for arm64." / "`macos-26-xlarge` – Extra-large runner for arm64." |
| `macos-26-intel`, `macos-26-large` (also `macos-latest-large`) | macOS 26, x64 (Intel) | GA | same README | "macOS 26 … x64 … `macos-latest-large`, `macos-26-intel`, `macos-26-large`" |
| `xcode-27` | macOS 27.0.1 (26A434), arm64 only | GA per changelog; the README badge still shows "preview" (stale, see note) | https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available ; README | "You can now use the generally available Xcode 27 runner image … this GitHub-hosted image runs on macOS 27 and includes the Xcode 27 toolchain and Apple SDKs." / "The image is available on Apple Silicon (arm64) runners only, not Intel runners." |
| `xcode-27-xlarge` | same image, larger arm64 runner | GA | same | "`xcode-27` / `xcode-27-xlarge`" |
| `macos-27`, `macos-27-xlarge`, `macos-27-large` | – | `Not documented in official sources` (absent from the README label table, the hosted-runner reference and both larger-runner tables) | https://docs.github.com/en/actions/reference/runners/larger-runners#available-macos-larger-runners-and-labels | The table lists only `macos-latest-xlarge`, `macos-15-xlarge`, `macos-26-xlarge`, `xcode-27-xlarge` (arm64) and `macos-latest-large`, `macos-15-large`, `macos-26-large` (Intel). |
| `macos-26-large` | Intel x64, 12 vCPU | Not an arm64 label | same | "Large … Intel … 12 … 30 GB … 14 GB … `macos-latest-large`, `macos-15-large` (latest), `macos-26-large`" |
| `macos-14` | – | Retired 2026-11-02 for arm64 | README banner | "All macOS 14 images retired from GitHub Actions on November 2, 2026." |

Which label gives macOS 27: only `xcode-27` (or `xcode-27-xlarge`). `macos-27` is not documented, so `xcode-27` is the only supported choice, not a second-best one. The changelog states the new support model: "Each image is based on a major Xcode version rather than the underlying operating system, and we will support one major Xcode version per image." (https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview). Consequence: the `macos-26` image carries only Xcode 26.x and the `xcode-27` image only Xcode 27.x.

Stale-doc note: the README badge for `xcode-27` still links the "public preview" issue while the changelog of 2026-10-15 declares GA. Support-policy text: "Beta Images … are excluded from the service level agreement" (https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Treat GA as the later, dated statement.

### 1b. Hardware (arm64)

| Runner | vCPU | RAM | Disk | Official URL | Quote |
|---|---|---|---|---|---|
| Standard arm64 (`macos-latest`, `macos-26`, `macos-15`, `xcode-27`) | 3 (M1) | 7 GB | 14 GB | https://docs.github.com/en/actions/reference/runners/github-hosted-runners | "macOS … 3 (M1) … 7 GB … 14 GB … arm64 … `macos-latest`, `macos-15`, `macos-26`, `xcode-27`" |
| XLarge arm64 (`macos-26-xlarge`, `xcode-27-xlarge`, `macos-latest-xlarge`) | 5 (M2) + 8 GPU hardware acceleration | 14 GB | 14 GB | https://docs.github.com/en/actions/reference/runners/larger-runners | "XLarge … arm64 (M2) … 5 (+ 8 GPU hardware acceleration) … 14 GB … 14 GB" |
| Standard Intel (`macos-26-intel`) | 4 | 14 GB | 14 GB | hosted-runner reference | "macOS … 4 … 14 GB … 14 GB … Intel" |
| Large Intel (`macos-26-large`) | 12 | 30 GB | 14 GB | larger-runners reference | "12 … 30 GB … 14 GB" |

Disk is 14 GB on every macOS runner: DerivedData, SPM checkouts, the `build-for-testing` products, the xcresult bundles and any downloaded artifact must all fit in it `[INFERENCE: no documented free-space figure for the image]`.

### 1c. Preinstalled Xcode

| Image | Xcodes installed | Default | Official URL | Quote |
|---|---|---|---|---|
| `macos-26` arm64 (image 20261102.0473.1, macOS 26.7.2) | 26.6, 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1 | 26.6 (`/Applications/Xcode.app` → `Xcode_26.6.app`) | https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md | "26.6 (default) \| 17F113 \| /Applications/Xcode_26.6.app \| /Applications/Xcode_26.6.0.app<br>/Applications/Xcode.app" ; SDK table "macOS 26.5 … 26.5, 26.6" |
| `xcode-27` arm64 (image 20261104.0337.1, macOS 27.0.1) | 27.2, 27.1, 27.0 | **27.1** (not 27.2) | https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md | "27.2 \| 27B52 \| /Applications/Xcode_27.2.app" ; "27.1 (default) \| 27A9275 \| /Applications/Xcode_27.1.app \| … /Applications/Xcode.app" |

Policy: "only one major version of Xcode will be supported per macOS version; all minor versions of the supported major version will be available; … when a new patch version is released, the previous patch version will be replaced" (README "Support Policy"). Consequence for the workflow: `/Applications/Xcode_26.6.app` is already the default on `macos-26`; on `xcode-27` selecting 27.2 is mandatory.

---

## Q2. Concurrency, queue limits, "not acquired by Runner", capacity

| Item | Fact | Official URL | Verbatim quote |
|---|---|---|---|
| macOS concurrent jobs per plan | Free 5, Pro 5, Team 5, Enterprise 50. The cap is shared between standard and larger runners. Total concurrent jobs (all OS): Free 20, Pro 40, Team 60, Enterprise 500; larger-runner total 1000. | https://docs.github.com/en/actions/reference/limits#job-concurrency-limits-for-github-hosted-runners | "Standard GitHub-hosted runner \| Team \| 60 \| 5" and "The maximum concurrent macOS jobs is shared across standard GitHub-hosted runners and GitHub-hosted larger runners." |
| Can the cap be raised | Yes, via GitHub Support | same | "GitHub Support **can** increase job concurrency limits for GitHub Actions. To request an increase, submit a support ticket." |
| Excess jobs | They queue | https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/view-current-jobs | "If you reach the maximum number of concurrent jobs, any new jobs will start to enter a queue." |
| Queue timeout for GitHub-hosted jobs | A queued run not processed by a GitHub-hosted runner within 45 minutes is discarded. The 24 h "Job queue time" row applies to self-hosted runners only. | https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#workflow-continuity ; https://docs.github.com/en/actions/reference/limits | "if the workflow run has been successfully queued, but has not been processed by a GitHub-hosted runner within 45 minutes, then the queued workflow run is discarded." / "Self-hosted \| Job queue time \| 24 hours" |
| Job run-time limit | 6 h per hosted job; `timeout-minutes` default 360 and counts run time, not queue time `[INFERENCE for the queue part]` | limits page; https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes | "Each job in a workflow can run for up to 6 hours of execution time." / "The maximum number of minutes to let a job run before GitHub automatically cancels it. Default: 360" |
| Matrix size | max 256 jobs per run | limits page | "A job matrix can generate a maximum of 256 jobs per workflow run." |
| Re-runs | up to 50 per run (failed-job re-run counts) | limits page | "A workflow run can be re-run a maximum of 50 times." |
| The annotation "The job was not acquired by Runner of type hosted even after multiple attempts" | `Not documented in official sources` (searched docs.github.com, github.blog/changelog, githubstatus.com; the only hits are community discussions, which are not admissible) | – | – |
| The notice "Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times" | `Not documented in official sources` | – | – |
| Documented mitigations for delay or non-start on larger runners | Check concurrency autoscaling setting, repository permission, billing, spending limit, fair-use throttling, and the queue-to-assign time of a smaller warm pool | https://docs.github.com/en/actions/reference/runners/larger-runners#troubleshooting-larger-runners | "Fair use policy: GitHub has a fair use policy that begins to throttle jobs based on several factors, such as how many jobs you are running or how many jobs are running across the entirety of GitHub Actions." / "Standard GitHub-hosted runners utilizing prescribed YAML workflow labels (such as `ubuntu-latest`) are always in a "warm" state. With larger runners, a warm VM may not be ready to pick up a job on first request as the pools for these machines are smaller. As a result, GitHub may need to create a new VM, which increases the queue to assign time." |
| Larger runners need a paid plan | Team or Enterprise Cloud, valid card, spending limit above zero | larger-runners reference + hosted-runner reference | "Larger runners are available for organizations and enterprises on GitHub Team and GitHub Enterprise Cloud plans." |
| Retry | Official mechanism: re-run failed jobs (limit above). An automatic job-level retry keyword: `Not documented in official sources` | limits page | – |
| Reducing macOS pressure | Fewer concurrent macOS jobs: `strategy.max-parallel` and `concurrency` (see Q4) | workflow-syntax | "By default, GitHub will maximize the number of jobs run in parallel depending on runner availability." |

Reading of the observed failure `[INFERENCE]`: `macos-26` and `xcode-27` draw on the same 5-job macOS concurrency cap, so the failure on `macos-26` while `xcode-27` was served cannot be explained by our own cap (only 2 macOS jobs were running); it points to pool-level capacity, which GitHub does not document. The documented levers are (i) fewer or shorter macOS jobs per run, (ii) re-run of the failed job, (iii) a larger runner whose pool has its own autoscaling limit but is documented as possibly slower to assign when cold.

---

## Q3. Handing build products between jobs; cache

### 3a. Artifact actions

| Item | Fact | Official URL | Verbatim quote |
|---|---|---|---|
| Current majors | `upload-artifact@v7`, `download-artifact@v8` | https://github.com/actions/upload-artifact (README) ; https://github.com/actions/download-artifact (README) | `- uses: actions/upload-artifact@v7` ; `- uses: actions/download-artifact@v8` |
| Retention | default 90 days (repository setting); 1–90 | upload-artifact README "Retention Period" | "Artifacts are retained for 90 days by default. … The retention period must be between 1 and 90 inclusive." |
| `compression-level` | 0–9, default 6; 0 for incompressible data | upload-artifact README | "The value can range from 0 to 9 … For large files that are not easily compressed, a value of `0` is recommended for significantly faster uploads." |
| `archive: false` (v7) | upload one file unzipped; artifact name = file name | upload-artifact README / v7.0.0 release notes | "If 'false', only a single file can be uploaded. The name of the file will be used as the artifact name" |
| Permission loss | zip upload resets modes to 755/644; official recommendation: tar and upload the tar with `archive: false` | upload-artifact README "Permission Loss"; download-artifact README "Maintaining File Permissions" | "File permissions are not maintained during zipped artifact upload. All directories will have `755` and all files will have `644`." / "If you must preserve permissions, you can `tar` all of your files together before artifact upload and upload that file directly with `archive: false`." |
| Artifacts per job | 500 (README of upload-artifact); the toolkit README still says 10, so the two official pages disagree | upload-artifact README "Number of Artifacts"; https://github.com/actions/toolkit/tree/main/packages/artifact | "Within an individual job, there is a limit of 500 artifacts that can be created for that job." vs "Each job in a workflow run now has a limit of 10 artifacts." |
| Same name twice | Not allowed; names unique, matrix jobs must add a suffix | upload-artifact README | "Unlike earlier versions of `upload-artifact`, uploading to the same artifact via multiple jobs is _not_ supported with `v4`." / "Artifact names must be unique since each created artifact is idempotent so multiple jobs cannot modify the same artifact." |
| Download | by `name`, `pattern` + `merge-multiple`, or `artifact-ids`; digest verified, mismatch is an error by default in v8 | download-artifact README; https://github.com/actions/download-artifact/releases/tag/v8.0.0 | "Hash mismatches will now error by default." |
| Maximum size of one artifact | `Not documented in official sources` (only plan storage quotas exist) | – | – |
| Behavior and speed with many small files | `Not documented in official sources` (README only advises compression level for large files; one tar of the products avoids the question `[INFERENCE]`) | – | – |
| Storage quota (shared with Packages) | Free 500 MB, Pro 1 GB, Team 2 GB, Enterprise 50 GB; beyond that billed $0.25/GB-month | https://docs.github.com/en/actions/reference/limits#storage-limits-for-all-github-hosted-runners ; https://docs.github.com/en/billing/concepts/product-billing/github-actions | "GitHub Team \| 2 GB \| $18 USD \| 10 GB" ; storage "billed based on hourly usage"; deleting does not refund accrued GB-hours |
| Artifacts vs cache guidance | Artifacts are the documented way to pass files between jobs; cache entries must be regenerable | https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts | "Use artifacts when you want to … pass files between jobs in a workflow." / "a job should always be able to re-download or regenerate these files if a cache isn't available" |
| Dynamic artifact per matrix cell | Documented pattern: job outputs + `fromJSON` + one artifact per matrix value | https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations#using-an-output-to-define-two-matrices | "You can use the output from one job to define matrices for multiple jobs." |

### 3b. Cache action

| Item | Fact | Official URL | Verbatim quote |
|---|---|---|---|
| Current major | `actions/cache@v6`; `actions/cache/restore@v6` and `actions/cache/save@v6` exist | https://github.com/actions/cache (README) ; https://github.com/actions/cache/releases/tag/v6.0.0 | "uses: actions/cache/restore@v6" / "uses: actions/cache/save@v6" ; v6: "Update packages, migrate to ESM" |
| Repository limit | 10 GB default (configurable up, extra storage billed); entries unused for 7 days removed; LRU eviction by last access | https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#usage-limits-and-eviction-policy | "GitHub will remove any cache entries that have not been accessed in over 7 days. … By default, the limit is 10 GB per repository … the cache eviction policy will create space by deleting the caches in order of last access date, from oldest to most recent." |
| Rate limits | 200 uploads/min, 1500 downloads/min per repository | same; limits page | "up to 200 uploads per minute per repository, and download them at a rate of 1500 downloads per minute per repository" |
| Key rules | max 512 characters; may use contexts and `hashFiles`; immutable once saved | dependency-caching reference | "Keys have a maximum length of 512 characters" / "You cannot change the contents of an existing cache." |
| `restore-keys` | ordered prefix list; on a prefix hit the most recently created entry wins; `cache-hit` is `true` only for an exact `key` match | same | "If there are multiple partial matches for a restore key, the action returns the most recently created cache." |
| Save timing | New entry is created only when the job completes successfully | same | "a new cache is automatically created if the job completes successfully." |
| Branch scope | current branch, then default branch; PR runs also base branch; PR-created caches live on `refs/pull/N/merge` and are restorable only by re-runs of that PR; sibling and child branches are isolated | same "Restrictions for accessing a cache" | "When a cache is created by a workflow run triggered on a pull request, the cache is created for the merge ref (`refs/pull/.../merge`). Because of this, the cache will have a limited scope and can only be restored by re-runs of the pull request." |
| Same-run sharing | Jobs of one run on the same ref can restore each other's entries | same | "A cache created for a branch in a workflow run can be accessed and restored from another workflow run for the same repository and branch." |
| Read-only access | `cache-mode` workflow/job key (`read`, `write`, `write-only`, `none`); low-trust triggers default to read | same; workflow-syntax `cache-mode` | "Use `cache-mode` to control the level of GitHub Actions cache access that jobs in the workflow are granted." |
| Minimum runner | v5+ needs runner 2.327.1 (Node 24); irrelevant for hosted runners | cache README | "`actions/cache@v5` runs on the Node.js 24 runtime and requires a minimum Actions Runner version of `2.327.1`." |

Use for our flow `[INFERENCE]`: keep `actions/cache` for the SPM checkout (`SourcePackages`) as today. For passing the compiled test products to shard jobs, artifacts are the documented mechanism; a cache keyed on `github.sha` would also work within one run but is documented as best-effort storage subject to eviction and the 10 GB shared pool.

---

## Q4. Matrix and orchestration features

| Feature | Fact | Official URL | Verbatim quote |
|---|---|---|---|
| `strategy.matrix` + `include` | `include` adds keys to matching combinations or creates new ones; arbitrary per-cell values (runner label, Xcode path, shard index, `primary`) | https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations#expanding-or-adding-matrix-configurations | "For each object in the `include` list, the key:value pairs in the object will be added to each of the matrix combinations if none of the key:value pairs overwrite any of the original matrix values. If the object cannot be added to any of the matrix combinations, a new matrix combination will be created instead." (workflow-syntax) |
| `fail-fast` | default `true`; cancels in-progress and queued matrix jobs on first failure; we already set `false` | workflow-syntax `#jobsjob_idstrategyfail-fast` | "GitHub will cancel all in-progress and queued jobs in the matrix if any job in the matrix fails. This property defaults to `true`." |
| `max-parallel` | caps simultaneous matrix jobs | https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations#defining-the-maximum-number-of-concurrent-jobs | "will run a maximum of two jobs at a time, even if there are runners available to run all six jobs at once." |
| Dynamic matrix | job output JSON → `fromJSON(needs.<job>.outputs.<name>)` as the whole `matrix` | https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#fromjson | "`matrix: ${{ fromJSON(needs.job1.outputs.matrix) }}`" with output `{"include":[{"project":"foo","config":"Debug"},…]}` |
| `needs` | dependent job is skipped if a needed job fails or is skipped unless a status function says otherwise | workflow-syntax `#jobsjob_idneeds` | "If a job fails or is skipped, all jobs that need it are skipped unless the jobs use a conditional expression that causes the job to continue." |
| Reusable workflows | `on: workflow_call`, called with `jobs.<id>.uses`; matrix may call them; up to 10 nesting levels; billing goes to the caller | https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows ; https://docs.github.com/en/actions/concepts/billing-and-usage | "Jobs using the matrix strategy can call a reusable workflow." / "If you reuse a workflow, billing is always associated with the caller workflow." |
| `concurrency` + `cancel-in-progress` | one running per group, newer pending replaces older pending; `cancel-in-progress: true` also cancels the running one (we already use it per ref); job-level `concurrency` can use `matrix`/`needs` contexts, so a group per OS is possible | workflow-syntax `#concurrency`, `#jobsjob_idconcurrency` | "To also cancel any currently running job or workflow in the same concurrency group, specify `cancel-in-progress: true`." |
| `timeout-minutes` | per job, default 360 | workflow-syntax `#jobsjob_idtimeout-minutes` | "The maximum number of minutes to let a job run before GitHub automatically cancels it. Default: 360" |
| Status functions | `success()` implicit; `always()` also runs when cancelled and the docs recommend `!cancelled()` instead; `failure()` is true when any previous step fails, and for chained jobs when any ancestor fails | https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions | "If you want to run a job or step regardless of its success or failure, use the recommended alternative: `if: ${{ !cancelled() }}`" |
| Job summaries | write Markdown to `$GITHUB_STEP_SUMMARY`; per-step 1 MiB cap; shown on the run page; secrets masked | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-job-summary | "Job summaries are isolated between steps and each step is restricted to a maximum size of 1MiB." |
| Merge of shard results | `Not documented in official sources` as a built-in; a final `needs: [shards]` job with `if: ${{ !cancelled() }}` downloads shard artifacts (`pattern` + `merge-multiple`) and runs `xcresulttool merge` / coverage gate `[INFERENCE]` | download-artifact README "Download multiple (filtered) Artifacts to the same directory" | "use the `pattern` and `merge-multiple` inputs" |

---

## Q5. Selecting an Xcode version on hosted macOS

| Item | Fact | Official URL | Verbatim quote |
|---|---|---|---|
| Where Xcode versions live | `/Applications/Xcode_<version>.app`, default symlinked at `/Applications/Xcode.app`; the exact list per image is in the image README, also linked from the job log "Set up job → Runner Image → Included Software" | image READMEs (Q1c); https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#preinstalled-software-for-github-owned-images | "Workflow logs include a link to the preinstalled tools on the exact runner." |
| GitHub-documented switch | `sudo xcode-select -s /Applications/Xcode_<v>.app` as a step (appears in GitHub's own build-and-test guide for Xamarin on the macOS runner) | https://docs.github.com/en/enterprise-server@3.14/actions/use-cases-and-examples/building-and-testing/building-and-testing-xamarin-applications | "XCODE_ROOT=/Applications/Xcode_12.3.0.app … sudo xcode-select -s $XCODE_ROOT" |
| The Swift guide | Documents `swift-actions/setup-swift` for Swift versions, not Xcode; no Xcode-selection recipe | https://docs.github.com/en/actions/tutorials/build-and-test-code/swift | "For a full list of up-to-date software and the preinstalled versions of Swift and Xcode, see GitHub-hosted runners." |
| `xcode-select` man page (shipped with Xcode; observed locally) | `--switch` needs sudo and is system-wide; `DEVELOPER_DIR` overrides it per process or shell session | `man xcode-select` (local) | "-s <path>, --switch <path> … This command must be run with superuser permissions (see sudo(8)), and will affect all users on the system. To set the path without superuser permissions or only for the current shell session, use the DEVELOPER_DIR environment variable instead" |
| `DEVELOPER_DIR` semantics | "When DEVELOPER_DIR is set, its value will be used instead of the system-wide active developer directory." | `man xcode-select`, `man xcrun` (local) | same sentence in both |
| Our repo | `Makefile:1-2` takes `XCODE_DEVELOPER_DIR` from the environment and exports `DEVELOPER_DIR`, so every `make` target already uses the matrix Xcode; `sudo xcode-select -s` only matters for the `python3 Scripts/coverage-report.py` step that runs outside `make` (it calls `xccov` through `xcrun`) `[INFERENCE for the last clause]`. Per-job env `DEVELOPER_DIR` would make the sudo step unnecessary. | `dreamder/Makefile`, `.github/workflows/dreamder.yml:50,77-78` | `export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)` |

---

## Q6. Billing

The documentation no longer publishes minute multipliers; it publishes per-minute USD rates. Ratios below are computed by me `[INFERENCE]` from those rates.

| Runner | SKU | USD per minute | Ratio to Linux 2-core ($0.006) | Official URL | Quote |
|---|---|---|---|---|---|
| macOS 3-core/4-core (M1 or Intel) – `macos-26`, `xcode-27`, `macos-26-intel` | `actions_macos` | $0.062 | ≈10.3× | https://docs.github.com/en/billing/reference/actions-runner-pricing | "macOS 3-core or 4-core (M1 or Intel) \| `actions_macos` \| $0.062" |
| macOS 12-core Intel (`macos-26-large`) | `macos_l` | $0.077 | ≈12.8× | same | "macOS 12-core \| `macos_l` \| $0.077" |
| macOS 5-core arm64 (`macos-26-xlarge`, `xcode-27-xlarge`) | `macos_xl` | $0.102 | 17× | same | "macOS 5-core (M2 Pro) \| `macos_xl` \| $0.102" |
| Rounding | each job rounded up to a whole minute | same | – | same | "GitHub rounds the minutes and partial minutes each job uses up to the nearest whole minute." |
| Public repositories | standard runners free; larger runners are billed | https://docs.github.com/en/billing/concepts/product-billing/github-actions | – | same | "Larger runners are billed for public repositories." / standard hosted runners free "In public repositories" |
| Included compute | monetary: Free $12, Pro $18, Team $18, Enterprise Cloud $300 per month | same | – | same | "The included compute usage is expressed as a monetary amount, not a fixed number of minutes" |
| Reusable workflow | billed to the caller | https://docs.github.com/en/actions/concepts/billing-and-usage | – | – | quoted in Q4 |

Cost of N parallel shard jobs on private repos: `cost = Σ over jobs of ceil(minutes_j) × $0.062` (standard arm64). Every extra shard repeats checkout, Xcode selection, SPM cache restore, artifact download and test-host start-up, so billed minutes rise while wall clock falls. Illustration with assumed figures `[INFERENCE]`: build job 8 min + 2 min artifact upload; tests are 20 min of work spread over N shards at 100 % scaling with 4 min overhead per shard: N=1 → 34 min billed (2.1 USD), N=3 → 10 + 3×(4+7) = 43 min (2.67 USD), N=4 → 10 + 4×(4+5) = 46 min (2.85 USD); per OS, double for two OSes. Wall clock falls from about 34 to about 21 (N=3) and about 19 (N=4) minutes.

---

## Q7. Action versions and breaking changes

| Action | Exists? | Breaking changes relevant to us | Official URL | Quote |
|---|---|---|---|---|
| `actions/checkout@v7` | Yes (v7.0.0, v7.0.1) | Refuses fork-PR checkout when triggered by `pull_request_target` or `workflow_run` unless `allow-unsafe-pr-checkout: true`; ESM migration. Our triggers are `push`/`pull_request`, so no effect. v5 raised the minimum runner to 2.327.1 (Node 24). `sparse-checkout` input unchanged. | https://github.com/actions/checkout (README, CHANGELOG.md) | "checkout now refuses to check out fork pull request code by default when the workflow is triggered by `pull_request_target` or `workflow_run`." |
| `actions/cache@v6` | Yes (v6.0.0) | ESM migration and package updates; no input changes listed. v5: Node 24, runner ≥ 2.327.1. | https://github.com/actions/cache/releases/tag/v6.0.0 ; README "What's New" | "Updated `@actions/cache`, `@actions/core`, `@actions/exec` to latest major versions · Migrated to ESM module system" |
| `actions/upload-artifact@v7` | Yes (v7.0.0, 2026-02-26) | New `archive` input (direct single-file upload, `name` ignored when `false`); ESM. Inherited from v4: immutable artifacts, unique names per run, no uploads to one name from several jobs; not on GHES. | https://github.com/actions/upload-artifact/releases/tag/v7.0.0 | "Callers can set the new `archive` parameter to `false` to skip zipping the file during upload." |
| `actions/download-artifact@v8` (latest major) | Yes (v8.0.0) | **Hash mismatch now fails the step by default** (`digest-mismatch: error`); non-zipped artifacts are detected by `Content-Type` and not unzipped; `skip-decompress`; ESM. A non-zipped download works only for artifacts uploaded with `upload-artifact@v7` and `archive: false`. | https://github.com/actions/download-artifact/releases/tag/v8.0.0 ; README | "Hash mismatches will now error by default. Users can override this behavior with a setting change" / "only supports files uploaded with `actions/upload-artifact@v7` and `archive: false` set" |

Pairing rule: use `upload-artifact@v7` with `download-artifact@v8` (the READMEs' own examples). The docs' tutorial pages still show v4/v5 in snippets; the action READMEs are the current source.

---

## Recommended topology

### Binding constraints from the documents above

- Standard arm64 runner: 3 vCPU / 7 GB / 14 GB disk; xlarge: 5 vCPU / 14 GB / 14 GB (Q1b).
- macOS concurrency: 5 jobs on Free/Pro/Team, 50 on Enterprise, shared between standard and larger runners (Q2).
- Queue: documented hold of 45 minutes, then the run is discarded; `macos-26` already failed to acquire a runner once; the root cause is `Not documented in official sources` (Q2).
- Price: $0.062 per minute per standard macOS job, rounded up per job; xlarge $0.102 (Q6).
- Artifact: tar plus `archive: false` preserves modes; one artifact per name; storage quota 500 MB–2 GB on non-Enterprise plans for private repos (Q3a).

### Option (a): one job per OS, one build, N test shards as parallel processes inside the job

| Aspect | Consequence |
|---|---|
| macOS jobs per run | 2 (one per OS); well below the cap of 5; fewest chances for a capacity failure at acquire time |
| CPU | Shards share 3 vCPU (standard) or 5 vCPU (xlarge). `dreamder/AGENTS.md` already records that "three hosts starve each other's process slots in git-heavy suites" locally and that CI runners are "3–5× slower"; on 3 vCPU the extra processes mostly contend `[INFERENCE]`. Gain is bounded by vCPU, so the 20 min test phase is unlikely to drop below about half |
| Disk and RAM | One checkout, one DerivedData; but N test hosts share 7 GB RAM and 14 GB disk |
| Billing | Lowest billed minutes (no repeated setup); one long job per OS |
| Artifact transfer | None |
| Failure blast radius | One failing shard process or one stuck host stalls the whole job; 60-minute timeout covers everything |
| Coverage | One xcresult per OS, merged locally (already implemented by `make coverage-sharded`) |
| Needs xlarge to pay off | `macos-26-xlarge` / `xcode-27-xlarge` (5 vCPU, 2× RAM) at 1.65× price per minute; requires Team/Enterprise plan and a possibly cold pool (Q2) |

### Option (b): one build job per OS uploads `build-for-testing` products; N shard jobs per OS download and run `test-without-building`

| Aspect | Consequence |
|---|---|
| macOS jobs per run | 2 builds + 2·N shards. Peak with N=3 is 6 concurrent if both builds finish together, above the cap of 5 on Free/Pro/Team: the sixth queues, which is the documented 45-minute discard risk. N=2 gives 4 peak jobs and leaves one slot. Enterprise (cap 50) has no practical limit `[INFERENCE]` |
| CPU | Each shard gets a full 3 vCPU VM: this is the only option whose speedup is not bounded by one machine's vCPU |
| Acquire risk | Every extra job is another acquire attempt on a pool that already failed once; with `fail-fast: false` a failed acquire costs one shard, and "re-run failed jobs" re-runs only that shard (limit 50 re-runs) |
| Billing | Billed minutes grow with N (repeated checkout, SPM cache restore, download, host start); see the Q6 illustration; wall clock shrinks |
| Artifact transfer | The product bundle is uploaded once per OS and downloaded N times. Size of our test products: unknown here; the documents give no size limit per artifact (`Not documented in official sources`), only plan quotas (Free 500 MB … Team 2 GB; Enterprise 50 GB) shared with Packages. Use `retention-days: 1`, one tar per OS (preserves modes and avoids per-file overhead), `archive: false` with `upload-artifact@v7`, and `download-artifact@v8` by name; choose `compression-level` only if `archive: true` (a pre-compressed `.tar.zst` is already incompressible; `zstd 1.5.7` is on the image) `[INFERENCE]` |
| Xcode requirement | Test products must be built and run with the same Xcode: pass `xcode-select`/`DEVELOPER_DIR` identically in both jobs; the product path stays valid only if moved with `-testProductsPath`/`.xctestrun` (both listed by local `xcodebuild -help`: `-xctestrun`, `-testProductsPath`, `-only-testing @<file>`) `[INFERENCE: path-relocation behavior of this project's hosted-app tests is not verified here]` |
| Orchestration | `build` → `needs` → matrix `shard: [1..N]` per OS (static `include` or `fromJSON` of a job output produced by `Scripts/sharded-tests.py`) → final `needs` job with `if: ${{ !cancelled() }}` downloading shard result artifacts, merging xcresults and running the 100 % coverage gate, writing `$GITHUB_STEP_SUMMARY` |
| Cache | SPM cache stays as today; each shard job restores it again, or skips it because the products are prebuilt and `test-without-building` does not resolve packages `[INFERENCE]` |
| Failure blast radius | One shard fails alone; coverage gate waits for all shards |

### Comparison

| Criterion | (a) in-job parallel | (b) build once + shard jobs |
|---|---|---|
| Speedup limit | vCPU of one VM (3 or 5) | number of VMs, capped by the macOS concurrency (5 on Free/Pro/Team) |
| Number of macOS acquires per run | 2 | 2 + 2·N |
| Capacity-failure exposure | lowest | grows with N; each failed shard is individually re-runnable |
| Billed minutes | lowest | higher (setup repeated N times) |
| Artifact quota pressure | none | one tar per OS per run; 1-day retention keeps accrual small |
| Complexity | already present (`make coverage-sharded`) | new workflow plumbing, merge job, product relocation |
| Fits the 100 % coverage gate | yes, merged locally | needs an explicit merge job |

### Recommendation `[INFERENCE]`

1. Keep one platform label per OS: `macos-26` (Xcode 26.6 is already the default, no switch needed) and `xcode-27` (the only documented macOS 27 label; select 27.2 by exporting `DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer` for the job, since the image default is 27.1).
2. On a plan with a macOS cap of 5, choose (b) with N=2 shards per OS (4 concurrent test jobs plus builds staggered by `needs`), or put the shard matrix under `strategy.max-parallel: 4`. Do not use N=3 unless the plan is Enterprise or Support raised the cap.
3. If the plan allows larger runners, a combination (a)+xlarge is the lowest-risk route to a shorter run (5 vCPU, 14 GB RAM, $0.102/min, 2 acquires per run), but the cold-pool warning in Q2 applies; (b) with xlarge shards multiplies that risk.
4. Under both options keep `fail-fast: false`, `timeout-minutes`, `concurrency` per ref with `cancel-in-progress: true` (cancelled runs release macOS slots immediately), upload logs with `if: ${{ !cancelled() }}` instead of `always()`, and write the coverage deltas to `$GITHUB_STEP_SUMMARY`.
5. Reserve a re-run of the failed job as the documented answer to `The job was not acquired by Runner of type hosted`; there is no documented configuration that prevents it.
