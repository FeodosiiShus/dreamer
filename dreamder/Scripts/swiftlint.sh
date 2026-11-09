#!/bin/sh
set -eu
artifacts="$1"
mode="$2"
baseline=Scripts/swiftlint-baseline.json
binary=$(find "$artifacts" -path '*swiftlint*macos*/bin/swiftlint.real' -type f 2>/dev/null | head -n 1)
if [ -z "$binary" ]; then
  echo "swiftlint: no real macOS binary under $artifacts; run make build first"
  exit 1
fi
if [ "$mode" = "baseline" ]; then
  "$binary" lint --quiet --config .swiftlint.yml --write-baseline "$baseline" Dreamder DreamderTests OpenWithDreamder >/dev/null || true
  echo "swiftlint: wrote $baseline"
else
  "$binary" lint --quiet --strict --config .swiftlint.yml --baseline "$baseline" Dreamder DreamderTests OpenWithDreamder
  echo "swiftlint: no violations beyond $baseline"
fi
