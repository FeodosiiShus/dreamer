#!/bin/sh
set -eu
swift "$(dirname "$0")/post.swift" toolwindow "$1"
