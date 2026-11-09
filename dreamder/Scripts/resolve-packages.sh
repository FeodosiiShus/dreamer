#!/bin/sh
set -eu
derived="$1"
shift
resolved=Dreamder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
stamp="$derived/.packages-resolved"
if [ -d "$derived/SourcePackages/checkouts" ] && [ -f "$stamp" ] && cmp -s "$resolved" "$stamp"; then
  exit 0
fi
mkdir -p .build/logs "$derived"
if ! "$@" -resolvePackageDependencies > .build/logs/resolve.log 2>&1; then
  echo "package resolution failed, see .build/logs/resolve.log"
  exit 1
fi
cp "$resolved" "$stamp"
