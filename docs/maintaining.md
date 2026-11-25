# Maintaining the tap

The tap keeps its packages up to date with little work by hand. A repository that publishes a release asks the tap,
through the action in this repository, to update a package to a version. The tap knows, for each package, how to
make that change and whether it lands as a pull request or as a commit to `main`. It checks the result with Homebrew
before delivering it, and the list of packages in the README follows on its own.

```text
other repository                 this tap
----------------                 --------
release published
  -> action.yml   --dispatch-->  update.yml -> scripts/update.sh
                                   reads packages/<name>.yml
                                   changes Formula/<name>.rb or Casks/<name>.rb
                                   checks it with scripts/check.sh
                                   opens a pull request, or commits to main
                                 readme.yml -> scripts/readme.sh
                                   rewrites the package list in README.md
```

## Layout

| Path                            | Contents                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------ |
| `Formula/<name>.rb`             | Formulae                                                                       |
| `Casks/<name>.rb`               | Casks                                                                          |
| `packages/<name>.yml`           | How a package is updated; without one, the tap does not update the package     |
| `packages/<name>.sh`            | The update script of a package that uses one                                   |
| `scripts/update.sh`             | Updates a package, checks it and delivers the change                           |
| `scripts/check.sh`              | Checks packages with `brew style`, `brew audit`, `brew install` and `brew test` |
| `scripts/readme.sh`             | Writes the package list into the README                                        |
| `scripts/lint.sh`               | Checks the scripts and every file in `packages/`                               |
| `scripts/lib.sh`                | Helpers shared by the scripts, and available to package scripts                |
| `action.yml`                    | The action other repositories use to ask for an update                         |
| `.github/workflows/update.yml`  | Runs an update, when asked by the action or by hand                            |
| `.github/workflows/tests.yml`   | Lints the tap and checks the changed packages, on pull requests and on `main`  |
| `.github/workflows/readme.yml`  | Keeps the package list in the README up to date                               |

## Adding a package

1. Write its formula in `Formula/<name>.rb` or its cask in `Casks/<name>.rb`, by hand. `brew create` drafts a
   formula from a URL, and the [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook) and the
   [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) describe both.
2. For the tap to update it, add `packages/<name>.yml`, and `packages/<name>.sh` if it uses a script. A package
   without one is listed in the README as updated by hand.
3. Open a pull request: `tests.yml` checks the new package.
4. In the package's own repository, add the action to the job that publishes its releases.

## How a package is updated

`packages/<name>.yml` holds three keys, all optional:

```yaml
# How the change lands: `pr` opens a pull request (the default), `commit` pushes to main.
delivery: pr

# How the files change: `bump` (the default) or `script`.
update: bump

# The extra arguments a caller may pass. Any other argument is refused.
args: []
```

An empty file takes every default. Any other key, or a value outside those listed, is an error.

### `bump`

`brew bump-formula-pr` or `brew bump-cask-pr`, without opening anything, sets the new version and recomputes the
URLs and checksums that depend on it. It suits a package whose download URLs follow from its version, as in
`url "https://example.com/example-#{version}.tar.gz"`, which is the common case.

### `script`

Runs `packages/<name>.sh`, for anything `bump` cannot do: a formula with a URL per architecture, a version that is
not in the URL, an argument such as a commit, or other files to change. The script runs with bash from the tap's
root, and receives:

| Variable     | Value                                                   |
| ------------ | ------------------------------------------------------- |
| `PACKAGE`    | The package's name                                      |
| `VERSION`    | The new version, without a leading `v`                  |
| `KIND`       | `formula` or `cask`                                     |
| `FILE`       | The path of its formula or cask                         |
| `TAP`        | The tap's name, `mariovagomarzal/tap`                   |
| `TAP_ROOT`   | The tap's root directory                                |
| `ARG_<NAME>` | Each argument the caller passed, its name in upper case |

It can `source "$TAP_ROOT/scripts/lib.sh"` for its helpers, such as `sha256_url`, which downloads a file and prints
its checksum. The updates run on macOS, so `sed -i` takes an empty suffix. For example:

```sh
#!/usr/bin/env bash
source "$TAP_ROOT/scripts/lib.sh"

url="https://github.com/mariovagomarzal/example/releases/download/v$VERSION/example-$VERSION.tar.gz"
sed -i '' -E \
  -e "s|^  url \".*\"|  url \"$url\"|" \
  -e "s|^  sha256 \".*\"|  sha256 \"$(sha256_url "$url")\"|" \
  "$FILE"
```

### What an update does

`scripts/update.sh <name> <version> [arguments]`, which `update.yml` runs:

1. **Checks the request.** The package must have its `packages/<name>.yml`, the version must look like one, and
   each argument must be one the package allows, with a value that is a string, a number or a boolean on one line.
   A leading `v` is dropped from the version.
2. **Does nothing** if Homebrew already sees the package at that version.
3. **Changes the files**, with `bump` or the script, and fails if nothing changed or if Homebrew then sees another
   version than the one asked for.
4. **Checks the package** with `scripts/check.sh`: `brew style`, `brew audit --strict --online`, `brew install`
   and, for a formula, `brew test`.
5. **Delivers the change**, with the message `feat(<name>): update to <version>`:
   - `pr`: pushes the branch `update/<name>` and opens a pull request from it. While that pull request is open, a
     newer version replaces the branch and updates the pull request instead of opening another.
   - `commit`: pushes to `main`, rebasing and trying again if `main` moved in between, and then starts `readme.yml`.

Updates of one package run one at a time: a request that arrives while another runs waits, and a newer request
waiting replaces an older one. Updates of different packages run side by side.

## Asking for an update from another repository

The repository runs the action in the job that publishes its releases:

```yaml
- uses: mariovagomarzal/homebrew-tap@v1
  with:
    token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
    package: example
    version: ${{ github.ref_name }}
    # Only for a package that allows them in its `args`:
    args: |
      commit=${{ github.sha }}
```

| Input        | Required | Value                                                                    |
| ------------ | -------- | ------------------------------------------------------------------------ |
| `token`      | Yes      | A token allowed to write this repository's contents                      |
| `package`    | Yes      | The formula or cask to update                                            |
| `version`    | Yes      | The new version; a leading `v`, as in a tag `v1.2.3`, is dropped         |
| `args`       | No       | Extra arguments, one `name=value` per line                               |
| `repository` | No       | The tap's repository, `mariovagomarzal/homebrew-tap` by default          |

The action sends a `repository_dispatch` event of type `update` to the tap, with the package, the version, the
arguments and a link to the run that sent it, which goes into the pull request. It does not wait for the update;
the tap's **Update** workflow shows how it went.

Run it in the same job that publishes the release. A release made with that job's `GITHUB_TOKEN` starts no other
workflow, so a separate workflow `on: release` would not run.

### The token

Sending an event to a repository takes a token that can write its contents; a repository's own `GITHUB_TOKEN`
cannot reach another one. The token is a
[fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with:

- **Repository access**: only `mariovagomarzal/homebrew-tap`.
- **Permissions**: **Contents: Read and write**.

Each repository that asks for updates keeps it as the secret `HOMEBREW_TAP_TOKEN`:

```sh
gh secret set HOMEBREW_TAP_TOKEN --repo mariovagomarzal/<repository>
```

When the token expires, create a new one and set the secret again in each of those repositories.

## Running an update by hand

From the **Update** workflow in the Actions tab, or:

```sh
gh workflow run update.yml --repo mariovagomarzal/homebrew-tap -f package=<name> -f version=<version>
gh workflow run update.yml --repo mariovagomarzal/homebrew-tap -f package=<name> -f version=<version> \
  -f args='{"commit": "<sha>"}' -f dry-run=true
```

By hand, the arguments are a JSON object. A dry run makes and checks the change without delivering it, which is how
to try a new `packages/<name>.yml` or script.

## The package list

The table in the README, between the `BEGIN PACKAGES` and `END PACKAGES` markers, is written by `scripts/readme.sh`
and is not edited by hand. It lists each formula and cask with the link, version and description Homebrew reads from
it, and how `packages/` says it is updated.

`readme.yml` runs it on every push to `main` that touches the packages, the scripts or the README, and commits the
table if it changed, as `docs(readme): update the package list`. Pushes made by a workflow start no other workflow, so
`scripts/update.sh` starts it after committing an update; an update delivered as a pull request reaches the list when
the pull request is merged.

## Checks

`tests.yml` runs on every pull request and every push to `main`:

- **Lint**, on Linux: `scripts/lint.sh` runs shellcheck on the scripts and validates every file in `packages/`.
- **Packages**, on macOS: `scripts/check.sh` on each formula and cask the change touches.

Pull requests opened by the update workflow do not start `tests.yml`, since they come from its `GITHUB_TOKEN`; the
update has run the same checks already, and the pull request links to that run.

## Repository settings

- **Settings → Actions → General → Workflow permissions**: allow GitHub Actions to create and approve pull requests,
  so that the update workflow can open them.

## The action's versions

Other repositories use the action by its major tag, `v1`. After changing `action.yml` in a compatible way, move the
tag to the new commit:

```sh
git tag --force v1 && git push --force origin v1
```

A change that breaks its callers gets a new tag, `v2`, and the callers move to it when they are ready.

## Commits

Commits follow [Conventional Commits](https://www.conventionalcommits.org), with the package as the scope when a
change is about one: `feat(<name>): add the formula`, `feat(<name>): update to <version>`,
`fix(<name>): ...`. Changes to the tap itself use the area instead, such as `ci`, `docs` or `feat(action)`.

## Working locally

`scripts/lint.sh` needs only `shellcheck`, `yq` and `jq`. The other scripts need Homebrew to see this checkout as
the tap, which CI does by linking it into Homebrew's taps. Where taps can be changed, the same link works locally:

```sh
mkdir -p "$(brew --repository)/Library/Taps/mariovagomarzal"
ln -s "$PWD" "$(brew --repository)/Library/Taps/mariovagomarzal/homebrew-tap"
DRY_RUN=1 scripts/update.sh <name> <version>
scripts/check.sh <name>
scripts/readme.sh
```

Where Homebrew's taps are fixed, as with nix-homebrew and `mutableTaps = false`, try an update in CI instead, with a
dry run of the **Update** workflow.
