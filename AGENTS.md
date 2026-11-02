# Repository Map

## Project

The goal is a code editor written in Swift, modeled on IntelliJ IDEA.
The existing IntelliJ sources provide the starting point and the architecture reference.

## Main directories

| Path | Contents |
| --- | --- |
| `platform/` | Shared IDE services, the editor, project models, indexing, and the UI. |
| `plugins/` | Language support, build tools, version control integrations, and other features. |
| `java/` | Java support, code analysis, completion, refactoring, and the debugger. |
| `python/` | Python support, helpers, and type stubs. |
| `jps/` | The project build system. |
| `fleet/` | Shared components from Fleet. |
| `native/` | Native components. |
| `libraries/`, `lib/` | Library modules and bundled dependencies. |
| `tools/` | Repository tools and test runners. |
| `tests/` | Tests for the repository and project structure. |
| `dreamder/` | The Swift app: the native macOS editor restyled as IntelliJ New UI. All new Swift code goes here. |

## Swift app (dreamder/)

`dreamder/` is the native macOS editor in Swift, forked from an MIT-licensed native editor; the IntelliJ sources in this repository are a behavior and asset reference only.
Before reading or changing anything under `dreamder/`, you MUST read `dreamder/AGENTS.md`; for that subtree it overrides this file.
Build, run, test, and capture screenshots from `dreamder/` only through `make` (`make build`, `make run`, `make test FILTER=…`, `make ui-test ONLY=…`, `make screenshot`); only one build or test command may run at a time.

## Editor reference

| Path | Area |
| --- | --- |
| `platform/editor-ui-api/src/com/intellij/openapi/editor/` | Editor interfaces, carets, selections, folding, inlays, and scrolling. |
| `platform/editor-ui-ex/src/com/intellij/openapi/editor/` | Extended editor interfaces and shared implementations. |
| `platform/core-impl/src/com/intellij/openapi/editor/impl/` | Document storage, text changes, and range markers. |
| `platform/platform-impl/src/com/intellij/openapi/editor/impl/` | The editor UI and its implementation. |
| `platform/lang-api/`, `platform/lang-impl/` | Language services and code insight. |
| `platform/analysis-api/`, `platform/analysis-impl/` | Code analysis. |
| `platform/indexing-api/`, `platform/indexing-impl/` | Indexing. |
| `platform/projectModel-api/`, `platform/projectModel-impl/` | Project and module models. |
| `platform/vfs-impl/` | The virtual file system. |
| `platform/execution/`, `platform/execution-impl/` | Run configurations and process execution. |
| `platform/xdebugger-api/`, `platform/xdebugger-impl/` | Debugger interfaces and UI. |
| `platform/vcs-api/`, `platform/vcs-impl/` | Version control services. |
| `platform/testFramework/` | Shared test infrastructure. |

## Module layout

- `*.iml` files define JPS modules and their dependencies.
- `BUILD.bazel` files describe Bazel targets. Many are generated from the JPS model.
- `src/` and `resources/` usually hold production code and resources.
- `testSrc/`, `tests/`, and `testData/` usually hold tests and their fixtures.
- Plugin descriptors usually live under `resources/META-INF/`.
