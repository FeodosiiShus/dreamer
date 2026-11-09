import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "DreamderTests")
LOGS = os.path.join(ROOT, ".build", "logs")
SHARDS_DIR = os.path.join(ROOT, ".build", "shards")
TARGET = "DreamderTests"
DESTINATION = "platform=macOS,arch=arm64"
UI_TARGET = "DreamderUITests"
FAILURE_LINE = re.compile(r"^✘ |^Restarting after|^/.*: error: |^xcode-select: error|^xcodebuild: error")
MAX_FAILURE_LINES = 60
STAGGER_SECONDS = 3
DERIVED = {"plain": "xcode", "coverage": "xcode-coverage"}

TOP_LEVEL = re.compile(
    r"(?m)^(?:@[\w.]+(?:\([^\n]*?\))?[ \t]+)*(?:(?:private|fileprivate|internal|public|final|nonisolated)\s+)*"
    r"(struct|class|enum|actor|extension)\s+(\w+)"
)
TEST_MARKER = re.compile(r"@Test\b|func test\w*\(")


def declaration_starts(text):
    starts = []
    for match in TOP_LEVEL.finditer(text):
        start = match.start()
        while start > 0:
            previous = text.rfind("\n", 0, start - 1) + 1
            if not text.startswith("@", previous):
                break
            start = previous
        starts.append((start, match.group(2)))
    return starts


def suites():
    weights = {}
    for directory, _, names in os.walk(TESTS):
        for name in names:
            if not name.endswith(".swift"):
                continue
            text = open(os.path.join(directory, name), encoding="utf-8", errors="ignore").read()
            starts = declaration_starts(text)
            for index, (start, suite) in enumerate(starts):
                end = starts[index + 1][0] if index + 1 < len(starts) else len(text)
                segment = text[start:end]
                count = len(TEST_MARKER.findall(segment))
                if count:
                    weight = count * (3 if ".uiGate" in segment or "@MainActor" in segment else 1)
                    weights[suite] = weights.get(suite, 0) + weight
    return weights


def partition(weights, count):
    bins = [[] for _ in range(count)]
    totals = [0] * count
    for name, weight in sorted(weights.items(), key=lambda item: (-item[1], item[0])):
        target = totals.index(min(totals))
        bins[target].append(name)
        totals[target] += weight
    return bins, totals


def selection(shards, index):
    if index < len(shards) - 1:
        return [f"-only-testing:{TARGET}/{name}" for name in shards[index]]
    assigned = [name for names in shards[:-1] for name in names]
    if not assigned:
        return [f"-only-testing:{TARGET}"]
    return [f"-skip-testing:{UI_TARGET}"] + [f"-skip-testing:{TARGET}/{name}" for name in assigned]


def test_run_specification(flavor):
    products = os.path.join(ROOT, ".build", DERIVED[flavor], "Build", "Products")
    found = sorted(glob.glob(os.path.join(products, "*.xctestrun")))
    if len(found) != 1:
        sys.exit(f"expected one .xctestrun in {os.path.relpath(products, ROOT)}, found {len(found)}; run make build-for-testing")
    return found[0]


def shard_command(flavor, shards, index, bundle):
    coverage = ["-enableCodeCoverage", "YES"] if flavor == "coverage" else []
    return [
        "xcodebuild", "test-without-building", "-xctestrun", test_run_specification(flavor),
        "-destination", DESTINATION, "-collect-test-diagnostics", "never", "-resultBundlePath", bundle,
    ] + coverage + selection(shards, index)


def start(flavor, shards, index):
    bundle = os.path.join(SHARDS_DIR, f"shard-{index}.xcresult")
    shutil.rmtree(bundle, ignore_errors=True)
    log_path = os.path.join(LOGS, f"shard-{index}.log")
    environment = dict(
        os.environ,
        TEST_RUNNER_DREAMDER_HEADLESS="1",
        TEST_RUNNER_SWIFT_DETERMINISTIC_HASHING="1",
        TEST_RUNNER_DREAMDER_SHARD=str(index),
    )
    with open(log_path, "w") as log:
        process = subprocess.Popen(
            shard_command(flavor, shards, index, bundle), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=environment
        )
    return process, log_path, time.monotonic()


def finish(index, process, log_path, started):
    code = process.wait()
    seconds = time.monotonic() - started
    print(f"shard {index}: {'passed' if code == 0 else 'FAILED'} in {seconds:.0f} s ({os.path.relpath(log_path, ROOT)})")
    if code != 0:
        with open(log_path, encoding="utf-8", errors="ignore") as log:
            failures = [line.rstrip() for line in log if FAILURE_LINE.search(line)]
        print("\n".join(failures[:MAX_FAILURE_LINES]))
    return code == 0


def merge(result):
    bundles = sorted(glob.glob(os.path.join(SHARDS_DIR, "shard-*.xcresult")))
    if not bundles:
        sys.exit(f"no shard result bundles in {os.path.relpath(SHARDS_DIR, ROOT)}")
    shutil.rmtree(result, ignore_errors=True)
    if len(bundles) > 1:
        subprocess.run(["xcrun", "xcresulttool", "merge", "--output-path", result] + bundles, cwd=ROOT, check=True)
    else:
        shutil.copytree(bundles[0], result)
    print(f"merged {len(bundles)} shard result(s): {os.path.relpath(result, ROOT)}")


def main():
    parser = argparse.ArgumentParser(description="Run DreamderTests split across test-host processes.")
    parser.add_argument("--shards", type=int, default=3)
    parser.add_argument("--only", type=int)
    parser.add_argument("--flavor", choices=sorted(DERIVED), default="plain")
    parser.add_argument("--result", default=os.path.join(ROOT, ".build", "sharded.xcresult"))
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--merge", action="store_true")
    arguments = parser.parse_args()

    if arguments.merge:
        merge(arguments.result)
        return 0

    count = max(1, arguments.shards)
    shards, totals = partition(suites(), count)
    if arguments.list:
        for index, names in enumerate(shards):
            remainder = " + every suite not listed in another shard" if index == count - 1 else ""
            print(f"shard {index}: {len(names)} suites, weight {totals[index]}{remainder}")
        return 0

    os.makedirs(LOGS, exist_ok=True)
    os.makedirs(SHARDS_DIR, exist_ok=True)

    if arguments.only is not None:
        if not 0 <= arguments.only < count:
            sys.exit(f"--only must be between 0 and {count - 1}")
        return 0 if finish(arguments.only, *start(arguments.flavor, shards, arguments.only)) else 1

    shutil.rmtree(SHARDS_DIR, ignore_errors=True)
    os.makedirs(SHARDS_DIR)
    running = []
    for index, names in enumerate(shards):
        if not names and index < count - 1:
            continue
        if running:
            time.sleep(STAGGER_SECONDS)
        running.append((index, *start(arguments.flavor, shards, index)))

    results = [finish(index, process, log_path, started) for index, process, log_path, started in running]
    merge(arguments.result)
    return 0 if all(results) else 1


sys.exit(main())
