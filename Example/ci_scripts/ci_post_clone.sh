#!/bin/zsh
set -e

# Xcode Cloud clones the repo fresh for every build and, like local dev,
# never sees a committed .xcodeproj (gitignored - XcodeGen owns it). This
# regenerates it from project.yml before the build proceeds. Runs in
# ci_post_clone (not ci_pre_xcodebuild) because Xcode Cloud's own build
# needs a real project to exist before it can do anything else.
brew install xcodegen

# $CI_PRIMARY_REPOSITORY_PATH is Xcode Cloud's own env var for the cloned
# repo root - more reliable than assuming this script's working directory,
# which Xcode Cloud doesn't guarantee.
cd "$CI_PRIMARY_REPOSITORY_PATH/Example"
xcodegen generate
