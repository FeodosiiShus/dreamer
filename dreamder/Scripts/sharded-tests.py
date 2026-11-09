import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "DreamderTests")
DERIVED = os.path.join(ROOT, ".build", "xcode")
LOGS = os.path.join(ROOT, ".build", "logs")
SHARDS_DIR = os.path.join(ROOT, ".build", "shards")
TARGET = "DreamderTests"
STAGGER_SECONDS = 3

TOP_LEVEL = re.compile(
    r"(?m)^(?:@[\w.]+(?:\([^\n]*?\))?[ \t]+)*(?:(?:private|fileprivate|internal|public|final|nonisolated)\s+)*"
    r"(struct|class|enum|actor|extension)\s+(\w+)"
)
TEST_MARKER = re.compile(r"@Test\b|func test\w*\(")


def xcodebuild_base():
    return [
        "xcodebuild", "-project", "Dreamder.xcodeproj", "-scheme", "Dreamder",
        "-configuration", "Debug", "-derivedDataPath", DERIVED,
        "-destination", "platform=macOS,arch=arm64",
        "-skipPackagePluginValidation", "-skipMacroValidation",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
        "PROVISIONING_PROFILE_SPECIFIER=", "ENABLE_HARDENED_RUNTIME=NO",
    ]


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
    return bins


def run(command, log_path, environment):
    with open(log_path, "w") as log:
        return subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=environment)


def main():
    parser = argparse.ArgumentParser(description="Run DreamderTests in several test-host processes at once.")
    parser.add_argument("--shards", type=int, default=3)
    parser.add_argument("--coverage", action="store_true")
    parser.add_argument("--result", default=os.path.join(ROOT, ".build", "sharded.xcresult"))
    arguments = parser.parse_args()

    os.makedirs(LOGS, exist_ok=True)
    shutil.rmtree(SHARDS_DIR, ignore_errors=True)
    os.makedirs(SHARDS_DIR)
    coverage = ["-enableCodeCoverage", "YES"] if arguments.coverage else []
    environment = dict(os.environ, TEST_RUNNER_DREAMDER_HEADLESS="1", TEST_RUNNER_SWIFT_DETERMINISTIC_HASHING="1")

    build_log = os.path.join(LOGS, "sharded-build.log")
    build = run(xcodebuild_base() + coverage + ["build-for-testing"], build_log, environment)
    if build.wait() != 0:
        print(f"build-for-testing failed, see {os.path.relpath(build_log, ROOT)}")
        return 1

    shards = partition(suites(), arguments.shards)
    processes = []
    bundles = []
    for index, names in enumerate(shards):
        if not names:
            continue
        bundle = os.path.join(SHARDS_DIR, f"shard-{index}.xcresult")
        bundles.append(bundle)
        selection = [f"-only-testing:{TARGET}/{name}" for name in names]
        shard_environment = dict(environment, TEST_RUNNER_DREAMDER_SHARD=str(index))
        command = xcodebuild_base() + coverage + [
            "test-without-building", "-collect-test-diagnostics", "never", "-resultBundlePath", bundle,
        ] + selection
        log_path = os.path.join(LOGS, f"shard-{index}.log")
        if processes:
            time.sleep(STAGGER_SECONDS)
        processes.append((index, run(command, log_path, shard_environment), log_path))

    failed = []
    for index, process, log_path in processes:
        code = process.wait()
        print(f"shard {index}: {'passed' if code == 0 else 'FAILED'} ({os.path.relpath(log_path, ROOT)})")
        if code != 0:
            failed.append(index)

    shutil.rmtree(arguments.result, ignore_errors=True)
    existing = [bundle for bundle in bundles if os.path.exists(bundle)]
    if len(existing) > 1:
        subprocess.run(["xcrun", "xcresulttool", "merge", "--output-path", arguments.result] + existing, cwd=ROOT, check=True)
    elif existing:
        shutil.copytree(existing[0], arguments.result)
    print(f"merged result: {os.path.relpath(arguments.result, ROOT)}")
    return 1 if failed else 0


sys.exit(main())
