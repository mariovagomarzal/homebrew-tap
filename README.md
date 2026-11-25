# homebrew-tap

My personal [Homebrew](https://brew.sh) tap, with formulae and casks for my own projects and a few others. When one
of them publishes a release, the tap updates its package by itself.

```sh
brew tap mariovagomarzal/tap
brew install mariovagomarzal/tap/<formula>
brew install --cask mariovagomarzal/tap/<cask>
```

## Packages

<!-- BEGIN PACKAGES: written by scripts/readme.sh -->

| Package | Kind | Version | Description | Updates |
| ------- | ---- | ------- | ----------- | ------- |
| [looper](https://mariovagomarzal.github.io/Looper/) | cask | 0.1.1 | Tiling window manager steered with the keyboard and a radial wheel | Automatic, by pull request |

<!-- END PACKAGES -->

How the tap works, how a package is added, and how another repository asks for an update:
[docs/maintaining.md](docs/maintaining.md).
