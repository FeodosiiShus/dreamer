#!/bin/sh
set -eu
swift "$(dirname "$0")/post.swift" merge "$1"
