#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cd "$ROOT"
git diff --check
git diff --cached --check
test -f Package.swift
test -f Resources/Info.plist
test -s Resources/IconSource.jpg
test -f Sources/CapswitchApp/MacOSInputController.swift
test -f Sources/CapswitchApp/InputSourceManager.swift
test -f Sources/CapswitchApp/ApplicationRelauncher.swift
test -f Sources/CapswitchApp/AppInstallationManager.swift
test -f Sources/CapswitchApp/LoginItemManager.swift
test -f Sources/CapswitchHID/CapswitchRemapping.c
grep -q 'CFBundleIconFile' Resources/Info.plist
grep -q 'dev.local.Capswitch' Resources/Info.plist
grep -q 'TISSelectInputSource' Sources/CapswitchApp/InputSourceManager.swift
grep -q 'IOHIDServiceClientSetProperty' Sources/CapswitchHID/CapswitchRemapping.c
grep -q '/usr/bin/open' Sources/CapswitchApp/ApplicationRelauncher.swift
grep -q 'SMAppService.mainApp' Sources/CapswitchApp/LoginItemManager.swift
test -f .forgejo/workflows/macos.yml
for name in build bundle test install doctor clean lint verify icon sign package publish-release setup-signing; do
  bash -n "scripts/$name.sh"
done
echo "lint: PASS"
