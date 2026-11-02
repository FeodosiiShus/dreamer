#!/bin/sh
set -eu
file="$1"
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
swift "$(dirname "$0")/post.swift" open "$file"
