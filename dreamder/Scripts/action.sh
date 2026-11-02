#!/bin/sh
set -eu
swift "$(dirname "$0")/post.swift" action "$1"
