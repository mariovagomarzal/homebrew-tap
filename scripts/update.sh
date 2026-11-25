#!/usr/bin/env bash
# Updates a package of the tap to a new version, checks it, and delivers the change as a pull request or a commit,
# following `packages/<package>.yml`.
#
#   scripts/update.sh <package> <version> [arguments]
#
# The arguments are a JSON object of extra values, which the package must allow in its `args`. A leading `v` is
# dropped from versions such as `v1.2.3`. With DRY_RUN=1 it stops after checking, leaving the change in place.
# SOURCE, a link to whatever asked for the update, and RUN_URL, a link to this run, go into the pull request.
source "$(dirname "$0")/lib.sh"

[[ $# -ge 2 && $# -le 3 ]] || die "usage: scripts/update.sh <package> <version> [arguments]"
package=$1
version=$2
args=${3:-}
[[ -z $args || $args == null ]] && args='{}'

find_package "$package"
read_package_config "$package"
tap=$(tap_name)

[[ $version =~ ^v[0-9] ]] && version=${version#v}
[[ $version =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || die "'$version' is not a valid version"

# Each argument the package allows reaches its script as ARG_<NAME>.
jq -e 'type == "object"' <<<"$args" >/dev/null 2>&1 || die "the arguments must be a JSON object, not '$args'"
while IFS= read -r name; do
  [[ $name =~ ^[a-z][a-z0-9_]*$ ]] || die "'$name' is not a valid argument name"
  grep -qxF "$name" <<<"$ALLOWED_ARGS" || die "$package does not take the argument '$name'"
  value=$(jq -r --arg name "$name" '.[$name] | if type == "string" or type == "number" or type == "boolean"
    then tostring else error("must be a string, a number or a boolean") end' <<<"$args") ||
    die "the argument '$name' must be a string, a number or a boolean"
  [[ $value != *$'\n'* ]] || die "the argument '$name' must fit in one line"
  export "ARG_$(tr '[:lower:]' '[:upper:]' <<<"$name")=$value"
done < <(jq -r 'keys[]' <<<"$args")

current=$(package_version "$package")
if [[ $current == "$version" ]]; then
  note "$package is already at $version"
  exit 0
fi
echo "Updating $package from $current to $version, with $UPDATE"

[[ -z $(git -C "$TAP_ROOT" status --porcelain) ]] || die "the working tree has changes; update from a clean one"

case $UPDATE in
  bump)
    brew "bump-$KIND-pr" --write-only --no-audit --no-browse --version="$version" "$tap/$package"
    ;;
  script)
    PACKAGE=$package VERSION=$version KIND=$KIND FILE=$FILE TAP=$tap bash "$TAP_ROOT/packages/$package.sh"
    ;;
esac

[[ -n $(git -C "$TAP_ROOT" status --porcelain) ]] || die "the update of $package changed nothing"
updated=$(package_version "$package")
[[ $updated == "$version" ]] || die "after the update $package is at $updated, not $version"

"$TAP_ROOT/scripts/check.sh" "$package"

if [[ ${DRY_RUN:-} == 1 ]]; then
  note "dry run: $package $version is checked and left uncommitted"
  exit 0
fi

title="feat($package): update to $version"
body="Updates \`$package\` from $current to $version."
[[ ${SOURCE:-} =~ ^https://[^[:space:]]+$ ]] && body+=$'\n\n'"Requested by $SOURCE."
[[ -n ${RUN_URL:-} ]] && body+=$'\n\n'"Made and checked in $RUN_URL."

cd "$TAP_ROOT"
base=$(git rev-parse --abbrev-ref HEAD)

case $DELIVERY in
  commit)
    git add --all
    git commit --quiet --message "$title"
    for attempt in 1 2 3; do
      if git push origin "HEAD:$base"; then
        note "$package $version committed to $base"
        # A push from a workflow starts no other workflow, so the README's package list is updated explicitly.
        if [[ ${GITHUB_ACTIONS:-} == true ]]; then
          gh workflow run readme.yml --ref "$base"
        fi
        exit 0
      fi
      echo "Push $attempt failed; rebasing on $base"
      git pull --rebase origin "$base"
    done
    die "could not push $package $version to $base"
    ;;
  pr)
    branch=update/$package
    git switch --quiet --force-create "$branch"
    git add --all
    git commit --quiet --message "$title"
    git push --force origin "$branch"
    if [[ $(gh pr view "$branch" --json state --jq .state 2>/dev/null) == OPEN ]]; then
      gh pr edit "$branch" --title "$title" --body "$body"
      note "$package $version: updated the open pull request from $branch"
    else
      gh pr create --base "$base" --head "$branch" --title "$title" --body "$body"
      note "$package $version: opened a pull request from $branch"
    fi
    ;;
esac
