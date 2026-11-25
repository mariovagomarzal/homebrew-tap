#!/usr/bin/env bash
# Checks the tap's own code: the scripts with shellcheck, and that every file in packages/ belongs to a package
# and is valid. Needs no Homebrew.
#
#   scripts/lint.sh
source "$(dirname "$0")/lib.sh"

shopt -s nullglob
shellcheck --external-sources --source-path="$TAP_ROOT/scripts" "$TAP_ROOT"/scripts/*.sh
# Package scripts receive PACKAGE, VERSION and the rest from `scripts/update.sh`, which shellcheck cannot see.
package_scripts=("$TAP_ROOT"/packages/*.sh)
if [[ ${#package_scripts[@]} -gt 0 ]]; then
  shellcheck --external-sources --source-path="$TAP_ROOT/scripts" --exclude=SC2153,SC2154 "${package_scripts[@]}"
fi

for config in "$TAP_ROOT"/packages/*.yml; do
  package=$(basename "$config" .yml)
  find_package "$package"
  read_package_config "$package"
  echo "packages/$package.yml: updates the $KIND $package with $UPDATE, delivered as a $DELIVERY"
done

for script in "$TAP_ROOT"/packages/*.sh; do
  package=$(basename "$script" .sh)
  [[ -f $TAP_ROOT/packages/$package.yml ]] || die "packages/$package.sh has no packages/$package.yml"
done
