#!/bin/sh
set -eu
dir="${1:-.build/annotate}"
case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
mkdir -p "$dir"
rm -f "$dir/annotate.txt"
swift "$(dirname "$0")/post.swift" annotate "$dir"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$dir/annotate.txt" ] && break
  sleep 0.5
done
cat "$dir/annotate.txt"
