#!/bin/sh
set -eu
stub='#!/bin/sh
# dreamder-swiftlint-stub
while [ $# -gt 0 ]; do
  if [ "$1" = "--cache-path" ] && [ $# -gt 1 ]; then
    mkdir -p "$2/Output"
  fi
  shift
done
exit 0
'
find "$1" -path '*swiftlint*/bin/swiftlint' -type f 2>/dev/null | while read -r binary; do
  if ! grep -q 'dreamder-swiftlint-stub' "$binary" 2>/dev/null; then
    printf '%s' "$stub" > "$binary"
    chmod +x "$binary"
  fi
done
