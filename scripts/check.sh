#!/usr/bin/env bash
# Checks packages of the tap: their style and audit, that they install, and that a formula passes its test.
# The tap has to be tapped, as `Homebrew/actions/setup-homebrew` does in CI.
#
#   scripts/check.sh <package>...
source "$(dirname "$0")/lib.sh"

[[ $# -ge 1 ]] || die "usage: scripts/check.sh <package>..."
tap=$(tap_name)

for package in "$@"; do
  find_package "$package"
  echo "Checking the $KIND $package"
  brew style "$FILE"
  brew audit --strict --online "--$KIND" "$tap/$package"
  case $KIND in
    formula)
      brew install --build-from-source --formula "$tap/$package"
      brew test "$tap/$package"
      ;;
    cask)
      brew install --cask "$tap/$package"
      ;;
  esac
done
