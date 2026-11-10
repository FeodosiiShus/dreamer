#!/bin/sh
set -eu
derived="$1"
shift
project=Dreamder.xcodeproj/project.pbxproj
resolved=Dreamder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
stamp="$derived/.packages-resolved"
signature() {
  cat "$resolved"
  awk '/Begin XCRemoteSwiftPackageReference section/,/End XCRemoteSwiftPackageReference section/' "$project"
}
if [ -d "$derived/SourcePackages/checkouts" ] && [ -f "$stamp" ] && signature | cmp -s - "$stamp"; then
  exit 0
fi
mkdir -p .build/logs "$derived"
if ! "$@" -resolvePackageDependencies > .build/logs/resolve.log 2>&1; then
  echo "package resolution failed, see .build/logs/resolve.log"
  exit 1
fi
signature > "$stamp"
