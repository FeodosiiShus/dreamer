#!/bin/sh
set -eu
dir="${1:-.build/screenshots/latest}"
case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
rm -rf "$dir"
mkdir -p "$dir"
for _ in $(seq 1 12); do
  swift "$(dirname "$0")/post.swift" snapshot "$dir"
  for _ in $(seq 1 10); do
    [ -f "$dir/windows.txt" ] && break 2
    sleep 0.5
  done
done
ls "$dir"/*.png
