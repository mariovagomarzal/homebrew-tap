#!/usr/bin/env bash
# Writes the list of packages into README.md, between its BEGIN PACKAGES and END PACKAGES markers: each formula and
# cask with the version and description Homebrew reads from it, and how `packages/` says it is updated. The tap has to
# be tapped, as for `scripts/check.sh`.
#
#   scripts/readme.sh
source "$(dirname "$0")/lib.sh"

[[ $# -eq 0 ]] || die "usage: scripts/readme.sh"
readme=$TAP_ROOT/README.md
begin='<!-- BEGIN PACKAGES: written by scripts/readme.sh -->'
end='<!-- END PACKAGES -->'
if ! grep -qxF "$begin" "$readme" || ! grep -qxF "$end" "$readme"; then
  die "README.md lacks the lines '$begin' and '$end'"
fi
tap=$(tap_name)

table=$(mktemp)
trap 'rm -f "$table"' EXIT

shopt -s nullglob
files=("$TAP_ROOT"/Formula/*.rb "$TAP_ROOT"/Casks/*.rb)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No packages yet." >"$table"
else
  {
    echo "| Package | Kind | Version | Description | Updates |"
    echo "| ------- | ---- | ------- | ----------- | ------- |"
  } >"$table"
  for file in "${files[@]}"; do
    package=$(basename "$file" .rb)
    find_package "$package"
    if [[ -f $TAP_ROOT/packages/$package.yml ]]; then
      read_package_config "$package"
      case $DELIVERY in
        pr) updates="Automatic, by pull request" ;;
        commit) updates="Automatic, by commit" ;;
      esac
    else
      updates="By hand"
    fi
    brew info --json=v2 "--$KIND" "$tap/$package" |
      jq -r --arg package "$package" --arg kind "$KIND" --arg updates "$updates" '
        (.formulae[0] // .casks[0]) as $info
        | [ (if $info.homepage then "[\($package)](\($info.homepage))" else $package end),
            $kind,
            ($info.versions.stable // $info.version),
            ($info.desc // ""),
            $updates ]
        | map(tostring | gsub("\\|"; "\\|") | gsub("\n"; " "))
        | "| " + join(" | ") + " |"' >>"$table"
  done
fi

# Replaces whatever is between the markers with the table.
updated=$(mktemp)
awk -v begin="$begin" -v end="$end" -v table="$table" '
  $0 == begin { print; print ""; while ((getline line < table) > 0) print line; print ""; skipping = 1; next }
  $0 == end { skipping = 0 }
  !skipping { print }
' "$readme" >"$updated"
mv "$updated" "$readme"
