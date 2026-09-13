#!/bin/zsh
set -e

# Runs after ci_post_clone has already regenerated the project - agvtool
# needs a real, existing .xcodeproj to act on, not project.yml. Must be the
# last thing to touch CURRENT_PROJECT_VERSION: nothing after this point may
# run `xcodegen generate` again, or it would overwrite agvtool's change
# with project.yml's own static CURRENT_PROJECT_VERSION and silently
# discard the real build number.
cd "$CI_PRIMARY_REPOSITORY_PATH/Example"

# `agvtool new-version -all` does two things: (1) sets CURRENT_PROJECT_VERSION
# in the pbxproj - the part that actually matters, since VERSIONING_SYSTEM=
# apple-generic means that's what becomes CFBundleVersion at build time -
# and (2) tries to also directly patch CFBundleVersion inside a real
# Info.plist *file*. With GENERATE_INFOPLIST_FILE: YES (no physical
# Info.plist - Xcode synthesizes it from build settings), step 2 has
# nothing to find and fails ("Cannot find .../YES", agvtool mangling the
# INFOPLIST_FILE build setting's value into a path) - a known agvtool
# limitation with generated-Info.plist projects, not a real problem, and
# step 1 already succeeded by the time it happens. Don't let that harmless
# failure abort the build via set -e - but do verify step 1 actually took
# effect before continuing, so a genuinely different agvtool failure still
# fails loudly instead of being silently swallowed.
xcrun agvtool new-version -all "$CI_BUILD_NUMBER" || true

actual_version=$(xcrun agvtool what-version -terse)
if [ "$actual_version" != "$CI_BUILD_NUMBER" ]; then
  echo "error: CURRENT_PROJECT_VERSION is '$actual_version', expected '$CI_BUILD_NUMBER' - agvtool failed for a real reason, not just the known Info.plist quirk."
  exit 1
fi
