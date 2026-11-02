#!/bin/sh
set -eu
dir="${OUT:-.build/menuitem}"
case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
mkdir -p "$dir"
rm -f "$dir/menuitem.txt"
swift "$(dirname "$0")/post.swift" menuitem "$dir|$1"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$dir/menuitem.txt" ] && break
  sleep 0.5
done
cat "$dir/menuitem.txt"
