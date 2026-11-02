import json
import os
import subprocess
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bundle = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, ".build", "coverage.xcresult")
sources = os.path.join(root, "Dreamder") + os.sep

report = json.loads(subprocess.run(
    ["xcrun", "xccov", "view", "--report", "--json", bundle],
    check=True, capture_output=True, text=True,
).stdout)

rows = []
for target in report.get("targets", []):
    if not target.get("name", "").startswith("Dreamder.app"):
        continue
    for file in target.get("files", []):
        if file["path"].startswith(sources) and file["executableLines"] > 0:
            rows.append((file["coveredLines"], file["executableLines"], os.path.relpath(file["path"], root)))

covered = sum(row[0] for row in rows)
executable = sum(row[1] for row in rows)
for row_covered, row_executable, path in sorted(rows, key=lambda row: row[0] / row[1]):
    print(f"{100 * row_covered / row_executable:6.1f}%  {row_covered:5d}/{row_executable:<5d} {path}")
if executable:
    print(f"\nDreamder app code: {100 * covered / executable:.1f}% ({covered}/{executable} lines, {len(rows)} files)")
