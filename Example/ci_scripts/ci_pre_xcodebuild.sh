#!/bin/zsh
set -e

# Runs after ci_post_clone has already regenerated the project - agvtool
# needs a real, existing .xcodeproj to act on, not project.yml. Must be the
# last thing to touch CURRENT_PROJECT_VERSION: nothing after this point may
# run `xcodegen generate` again, or it would overwrite agvtool's change
# with project.yml's own static CURRENT_PROJECT_VERSION and silently
# discard the real build number.
cd "$CI_PRIMARY_REPOSITORY_PATH/Example"
xcrun agvtool new-version -all "$CI_BUILD_NUMBER"
