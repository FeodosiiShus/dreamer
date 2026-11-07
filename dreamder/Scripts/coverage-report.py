import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Dreamder") + os.sep
DEFAULT_BUNDLE = os.path.join(ROOT, ".build", "coverage.xcresult")
DEFAULT_SCOPES = os.path.join(ROOT, "Scripts", "coverage-scopes.json")
DEFAULT_BASELINE = os.path.join(ROOT, "Scripts", "coverage-baseline.json")

LOGIC_SCOPES = ("pure", "viewModel", "io")
ALL_SCOPES = LOGIC_SCOPES + ("view",)
UNCLASSIFIED = "unclassified"

TOTAL_TOLERANCE_PP = 1.0
SCOPE_TOLERANCE_PP = 1.0
FILE_FLOOR_PERCENT = 80.0
FILE_TOLERANCE_PP = 5.0
NEW_FILE_MINIMUM_PERCENT = 70.0
EPSILON = 1e-9

EXIT_REGRESSION = 1
EXIT_CONFIGURATION = 2


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(EXIT_CONFIGURATION)


def percent(covered, executable):
    return 100.0 * covered / executable if executable else 0.0


def toolchain_identifier():
    completed = subprocess.run(["xcrun", "swift", "--version"], capture_output=True, text=True)
    match = re.search(r"Swift version (\d+)\.(\d+)", completed.stdout + completed.stderr)
    if not match:
        fail("cannot determine the Swift toolchain version from `xcrun swift --version`")
    return f"swift-{match.group(1)}.{match.group(2)}"


def read_json(path, description):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        fail(f"cannot read {description} {os.path.relpath(path, ROOT)}: {error}")


def load_rows(bundle):
    if not os.path.exists(bundle):
        fail(f"coverage bundle {bundle} not found; run `make coverage` first")
    completed = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", bundle],
        capture_output=True, text=True,
    )
    if completed.returncode != 0:
        fail(f"xccov failed for {bundle}: {completed.stderr.strip()}")
    report = json.loads(completed.stdout)
    rows = {}
    for target in report.get("targets", []):
        if not target.get("name", "").startswith("Dreamder.app"):
            continue
        for file in target.get("files", []):
            if file["path"].startswith(SOURCES) and file["executableLines"] > 0:
                path = os.path.relpath(file["path"], ROOT)
                rows.setdefault(path, (file["coveredLines"], file["executableLines"]))
    return rows


def glob_to_regex(pattern):
    parts = []
    index = 0
    while index < len(pattern):
        if pattern.startswith("**/", index):
            parts.append("(?:.*/)?")
            index += 3
        elif pattern.startswith("**", index):
            parts.append(".*")
            index += 2
        elif pattern[index] == "*":
            parts.append("[^/]*")
            index += 1
        elif pattern[index] == "?":
            parts.append("[^/]")
            index += 1
        else:
            parts.append(re.escape(pattern[index]))
            index += 1
    return re.compile("".join(parts) + r"\Z")


def specificity(pattern):
    return len(pattern.replace("*", "").replace("?", ""))


class Classifier:
    def __init__(self, scopes):
        self.entries = []
        for scope, patterns in scopes.items():
            if scope not in ALL_SCOPES:
                fail(f"unknown scope '{scope}' in coverage-scopes.json")
            for pattern in patterns:
                self.entries.append((specificity(pattern), scope, glob_to_regex(pattern)))

    def classify(self, path):
        relative = path[len("Dreamder/"):] if path.startswith("Dreamder/") else path
        best = -1
        winners = set()
        for weight, scope, regex in self.entries:
            if not regex.match(relative):
                continue
            if weight > best:
                best = weight
                winners = {scope}
            elif weight == best:
                winners.add(scope)
        if len(winners) == 1:
            return next(iter(winners))
        return None


def load_classifier(path):
    scopes = read_json(path, "scopes")
    if scopes is None:
        return None
    return Classifier(scopes)


def classify_rows(rows, classifier):
    files = {}
    for path, (covered, executable) in rows.items():
        scope = classifier.classify(path) if classifier else None
        files[path] = {"covered": covered, "executable": executable, "scope": scope or UNCLASSIFIED}
    return files


def summarize(files):
    total = {"covered": 0, "executable": 0}
    scopes = {scope: {"covered": 0, "executable": 0} for scope in ALL_SCOPES}
    for entry in files.values():
        total["covered"] += entry["covered"]
        total["executable"] += entry["executable"]
        bucket = scopes.get(entry["scope"])
        if bucket is not None:
            bucket["covered"] += entry["covered"]
            bucket["executable"] += entry["executable"]
    return {"total": total, "scopes": scopes, "files": files}


def logic_totals(snapshot):
    covered = sum(snapshot["scopes"][scope]["covered"] for scope in LOGIC_SCOPES)
    executable = sum(snapshot["scopes"][scope]["executable"] for scope in LOGIC_SCOPES)
    return {"covered": covered, "executable": executable}


def entry_percent(entry):
    return percent(entry["covered"], entry["executable"])


def render_text(snapshot):
    lines = []
    files = snapshot["files"]
    for path, entry in sorted(files.items(), key=lambda item: entry_percent(item[1])):
        lines.append(f"{entry_percent(entry):6.1f}%  {entry['covered']:5d}/{entry['executable']:<5d} {path}")
    lines.append("")
    for scope in ALL_SCOPES:
        bucket = snapshot["scopes"][scope]
        count = sum(1 for entry in files.values() if entry["scope"] == scope)
        lines.append(
            f"scope {scope:<9} {entry_percent(bucket):5.1f}% ({bucket['covered']}/{bucket['executable']} lines, {count} files)"
        )
    unclassified = sorted(path for path, entry in files.items() if entry["scope"] == UNCLASSIFIED)
    if unclassified:
        lines.append(f"scope {UNCLASSIFIED:<9} {len(unclassified)} files")
    total = snapshot["total"]
    if total["executable"]:
        lines.append("")
        lines.append(
            f"Dreamder app code: {entry_percent(total):.1f}% ({total['covered']}/{total['executable']} lines, {len(files)} files)"
        )
    return "\n".join(lines)


def check(snapshot, baseline):
    violations = []
    files = snapshot["files"]

    unclassified = sorted(path for path, entry in files.items() if entry["scope"] == UNCLASSIFIED)
    for path in unclassified:
        violations.append(f"unclassified file (add it to Scripts/coverage-scopes.json): {path}")

    current_total = entry_percent(snapshot["total"])
    baseline_total = entry_percent(baseline["total"])
    if baseline_total - current_total > TOTAL_TOLERANCE_PP + EPSILON:
        violations.append(
            f"total coverage {current_total:.2f}% is more than {TOTAL_TOLERANCE_PP} pp below baseline {baseline_total:.2f}%"
        )

    for scope in LOGIC_SCOPES:
        baseline_scope = baseline["scopes"].get(scope)
        if baseline_scope is None:
            continue
        current_scope = entry_percent(snapshot["scopes"][scope])
        reference = entry_percent(baseline_scope)
        if reference - current_scope > SCOPE_TOLERANCE_PP + EPSILON:
            violations.append(
                f"scope {scope} coverage {current_scope:.2f}% is more than {SCOPE_TOLERANCE_PP} pp below baseline {reference:.2f}%"
            )

    baseline_files = baseline["files"]
    for path, entry in sorted(files.items()):
        previous = baseline_files.get(path)
        current_percent = entry_percent(entry)
        if previous is None:
            if entry["scope"] in LOGIC_SCOPES and entry["covered"] * 100 < NEW_FILE_MINIMUM_PERCENT * entry["executable"]:
                violations.append(
                    f"new {entry['scope']} file {path} has {current_percent:.1f}% coverage, minimum is {NEW_FILE_MINIMUM_PERCENT:.0f}%"
                )
            continue
        previous_percent = entry_percent(previous)
        if previous_percent >= FILE_FLOOR_PERCENT and previous_percent - current_percent > FILE_TOLERANCE_PP + EPSILON:
            violations.append(
                f"{path} dropped from {previous_percent:.1f}% to {current_percent:.1f}% (limit {FILE_TOLERANCE_PP} pp for files at or above {FILE_FLOOR_PERCENT:.0f}%)"
            )
    return violations


def delta_cell(current, reference):
    if reference is None:
        return "n/a"
    return f"{current - reference:+.2f}"


def render_summary(snapshot, baseline, violations):
    total = snapshot["total"]
    lines = ["## Dreamder coverage", ""]
    lines.append("| Scope | Lines | Coverage | Baseline | Delta (pp) |")
    lines.append("|---|---:|---:|---:|---:|")
    rows = [("total", total, baseline["total"] if baseline else None)]
    rows.append(("logic", logic_totals(snapshot), logic_totals(baseline) if baseline else None))
    for scope in ALL_SCOPES:
        reference = baseline["scopes"].get(scope) if baseline else None
        rows.append((scope, snapshot["scopes"][scope], reference))
    for name, bucket, reference in rows:
        current = entry_percent(bucket)
        reference_percent = entry_percent(reference) if reference else None
        baseline_cell = f"{reference_percent:.2f}%" if reference_percent is not None else "n/a"
        lines.append(
            f"| {name} | {bucket['covered']}/{bucket['executable']} | {current:.2f}% | {baseline_cell} | {delta_cell(current, reference_percent)} |"
        )
    lines.append("")
    if violations is None:
        lines.append("Gate: not enforced on this run.")
    elif violations:
        lines.append(f"Gate: **failed** ({len(violations)} violation{'s' if len(violations) != 1 else ''})")
        lines.append("")
        lines.extend(f"- {violation}" for violation in violations)
    else:
        lines.append("Gate: **passed**")
    weakest = sorted(
        (item for item in snapshot["files"].items() if item[1]["scope"] in LOGIC_SCOPES),
        key=lambda item: (entry_percent(item[1]), -item[1]["executable"]),
    )[:10]
    if weakest:
        lines.append("")
        lines.append("Lowest-covered logic files")
        lines.append("")
        lines.append("| File | Scope | Coverage | Lines |")
        lines.append("|---|---|---:|---:|")
        for path, entry in weakest:
            lines.append(f"| `{path}` | {entry['scope']} | {entry_percent(entry):.1f}% | {entry['covered']}/{entry['executable']} |")
    return "\n".join(lines) + "\n"


def write_json(path, snapshot):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(snapshot, handle, indent=1, sort_keys=True)
        handle.write("\n")


def validate_baseline(baseline, path):
    required = ("total", "scopes", "files")
    if not isinstance(baseline, dict) or any(key not in baseline for key in required):
        fail(f"{os.path.relpath(path, ROOT)} is malformed; regenerate it with `make coverage-baseline`")


def main():
    parser = argparse.ArgumentParser(description="Per-file and per-scope line coverage of the Dreamder app sources.")
    parser.add_argument("bundle", nargs="?", default=DEFAULT_BUNDLE)
    parser.add_argument("--json", metavar="OUT", help="write total, scopes and files as JSON")
    parser.add_argument("--check", action="store_true", help="fail when coverage regresses against the baseline")
    parser.add_argument("--summary", action="store_true", help="append a markdown summary to $GITHUB_STEP_SUMMARY, or print it")
    parser.add_argument("--write-baseline", action="store_true", help="write the baseline JSON from this run")
    parser.add_argument("--scopes", default=DEFAULT_SCOPES)
    parser.add_argument("--baseline", default=DEFAULT_BASELINE)
    arguments = parser.parse_args()

    classifier = load_classifier(arguments.scopes)
    if classifier is None and (arguments.check or arguments.write_baseline):
        fail(f"scopes file {os.path.relpath(arguments.scopes, ROOT)} not found")

    snapshot = summarize(classify_rows(load_rows(arguments.bundle), classifier))
    quiet = arguments.check or arguments.write_baseline or arguments.summary

    if not quiet:
        print(render_text(snapshot))
    if arguments.json:
        write_json(arguments.json, snapshot)
        if not quiet:
            print(f"\nWrote {arguments.json}")

    baseline = None
    if arguments.check or arguments.summary:
        baseline = read_json(arguments.baseline, "baseline")
        if baseline is not None:
            validate_baseline(baseline, arguments.baseline)

    violations = None
    exit_code = 0
    if arguments.check:
        if baseline is None:
            print(
                f"error: baseline {os.path.relpath(arguments.baseline, ROOT)} not found; "
                "generate it with `make coverage-baseline` and commit it",
                file=sys.stderr,
            )
            exit_code = EXIT_CONFIGURATION
        elif baseline.get("toolchain") not in (None, toolchain_identifier()):
            print(
                f"Coverage check skipped: baseline was written with {baseline['toolchain']}, "
                f"this run uses {toolchain_identifier()}; line counts differ between toolchains"
            )
        else:
            violations = check(snapshot, baseline)
            if violations:
                print(f"Coverage check failed ({len(violations)} violation{'s' if len(violations) != 1 else ''}):")
                for violation in violations:
                    print(f"  {violation}")
                exit_code = EXIT_REGRESSION
            else:
                total = snapshot["total"]
                print(f"Coverage check passed: total {entry_percent(total):.2f}%, logic {entry_percent(logic_totals(snapshot)):.2f}%")

    if arguments.summary:
        markdown = render_summary(snapshot, baseline, violations)
        destination = os.environ.get("GITHUB_STEP_SUMMARY")
        if destination:
            with open(destination, "a", encoding="utf-8") as handle:
                handle.write(markdown)
        else:
            print(markdown)

    if arguments.write_baseline:
        unclassified = sorted(path for path, entry in snapshot["files"].items() if entry["scope"] == UNCLASSIFIED)
        if unclassified:
            print("error: cannot write a baseline while files are unclassified:", file=sys.stderr)
            for path in unclassified:
                print(f"  {path}", file=sys.stderr)
            sys.exit(EXIT_CONFIGURATION)
        write_json(arguments.baseline, {**snapshot, "toolchain": toolchain_identifier()})
        total = snapshot["total"]
        print(
            f"Wrote {os.path.relpath(arguments.baseline, ROOT)}: total {entry_percent(total):.2f}%, "
            f"logic {entry_percent(logic_totals(snapshot)):.2f}%, {len(snapshot['files'])} files"
        )

    sys.exit(exit_code)


main()
