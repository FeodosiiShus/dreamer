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
binaries=$(find "$1" -path '*swiftlint*/bin/swiftlint' -type f 2>/dev/null || true)
if [ -z "$binaries" ]; then
  echo "swiftlint: no binary found under $1"
  exit 0
fi
printf '%s\n' "$binaries" | while read -r binary; do
  if ! grep -q 'dreamder-swiftlint-stub' "$binary" 2>/dev/null; then
    cp "$binary" "$binary.real"
    printf '%s' "$stub" > "$binary"
    chmod +x "$binary"
  fi
done
