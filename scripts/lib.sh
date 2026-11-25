# shellcheck shell=bash
# Shared by the tap's scripts, and available to package scripts with
# `source "$TAP_ROOT/scripts/lib.sh"`. Written for the bash 3.2 that macOS ships.

# The functions set globals for whoever sources this file.
# shellcheck disable=SC2034
set -euo pipefail

TAP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export TAP_ROOT

# Stops with an error, shown as an annotation when running in GitHub Actions.
die() {
  echo "::error::$*" >&2
  exit 1
}

note() {
  echo "::notice::$*"
}

# The tap's name, `owner/tap` for the repository `owner/homebrew-tap`.
tap_name() {
  local repo=${GITHUB_REPOSITORY:-}
  if [[ -z $repo ]]; then
    repo=$(git -C "$TAP_ROOT" remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#') || true
  fi
  [[ $repo =~ ^([^/]+)/homebrew-(.+)$ ]] || die "cannot tell the tap's name from the repository '$repo'"
  echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]'
}

# Finds a package's file and sets KIND (formula or cask) and FILE.
find_package() {
  local package=$1
  [[ $package =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || die "'$package' is not a valid package name"
  local formula=$TAP_ROOT/Formula/$package.rb cask=$TAP_ROOT/Casks/$package.rb
  if [[ -f $formula && -f $cask ]]; then
    die "$package is both a formula and a cask"
  elif [[ -f $formula ]]; then
    KIND=formula FILE=$formula
  elif [[ -f $cask ]]; then
    KIND=cask FILE=$cask
  else
    die "the tap has no formula or cask named $package"
  fi
}

# Reads `packages/<package>.yml`, the instructions to update a package, and sets DELIVERY, UPDATE and
# ALLOWED_ARGS (one name per line). Fails when the file is missing or says something unexpected.
read_package_config() {
  local package=$1 config=$TAP_ROOT/packages/$1.yml
  [[ -f $config ]] || die "packages/$package.yml does not exist: the tap does not update $package"
  command -v yq >/dev/null || die "yq is needed to read packages/$package.yml"

  local keys
  keys=$(yq -r '(. // {}) | keys | .[]' "$config")
  local key
  for key in $keys; do
    case $key in
      delivery | update | args) ;;
      *) die "packages/$package.yml: unknown key '$key'" ;;
    esac
  done

  DELIVERY=$(yq -r '.delivery // "pr"' "$config")
  case $DELIVERY in
    pr | commit) ;;
    *) die "packages/$package.yml: delivery is '$DELIVERY', and must be pr or commit" ;;
  esac

  UPDATE=$(yq -r '.update // "bump"' "$config")
  case $UPDATE in
    bump) ;;
    script) [[ -f $TAP_ROOT/packages/$package.sh ]] || die "packages/$package.yml: update is script, but packages/$package.sh does not exist" ;;
    *) die "packages/$package.yml: update is '$UPDATE', and must be bump or script" ;;
  esac

  ALLOWED_ARGS=$(yq -r '.args // [] | .[]' "$config")
  local name
  for name in $ALLOWED_ARGS; do
    [[ $name =~ ^[a-z][a-z0-9_]*$ ]] || die "packages/$package.yml: '$name' is not a valid argument name"
  done
}

# The version of a package as Homebrew sees it.
package_version() {
  local package=$1
  find_package "$package"
  brew info --json=v2 "--$KIND" "$(tap_name)/$package" |
    jq -r '.formulae[0].versions.stable // .casks[0].version'
}

# The SHA-256 checksum of the file at a URL, for package scripts.
sha256_url() {
  curl --fail --silent --show-error --location --retry 3 "$1" | shasum -a 256 | cut -d ' ' -f 1
}
