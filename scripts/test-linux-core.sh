#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

if [[ "$IS_MACOS" == 1 ]]; then
  echo "Linux-only test fixture must not be used on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain is required for Linux core tests." >&2
  exit 1
fi

# The normal Package.swift targets AppKit, Carbon and IOKit. None of those
# frameworks exist in Linux containers. Build only the pure Swift core and
# its real XCTest suite in a temporary, independent SwiftPM package.
temporary_package="$(mktemp -d)"
trap 'rm -rf "$temporary_package"' EXIT
mkdir -p \
  "$temporary_package/Sources/CapswitchCore" \
  "$temporary_package/Tests/CapswitchCoreTests"

cp "$ROOT"/Sources/Capswitch/*.swift \
  "$temporary_package/Sources/CapswitchCore/"
cp "$ROOT"/Tests/CapswitchCoreTests/*.swift \
  "$temporary_package/Tests/CapswitchCoreTests/"

cat > "$temporary_package/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macoc-LinuxCoreTests",
    products: [
        .library(name: "CapswitchCore", targets: ["CapswitchCore"]),
    ],
    targets: [
        .target(name: "CapswitchCore"),
        .testTarget(
            name: "CapswitchCoreTests",
            dependencies: ["CapswitchCore"]
        ),
    ]
)
SWIFT

swift test --package-path "$temporary_package" --jobs 2
