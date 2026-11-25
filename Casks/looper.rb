cask "looper" do
  version "0.1.1"
  sha256 "34664af14634dae7c673cecb1d6bc74e86f29c60aa7db00ea970c491208910c3"

  url "https://github.com/mariovagomarzal/Looper/releases/download/v#{version}/Looper-v#{version}.zip"
  name "Looper"
  desc "Tiling window manager steered with the keyboard and a radial wheel"
  homepage "https://mariovagomarzal.github.io/Looper/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :golden_gate

  app "Looper-v#{version}/Looper.app"
  binary "Looper-v#{version}/bin/looper"
  bash_completion "Looper-v#{version}/shell-completion/looper.bash"
  fish_completion "Looper-v#{version}/shell-completion/looper.fish"
  zsh_completion "Looper-v#{version}/shell-completion/_looper"

  # Looper is signed with its own certificate and not notarised, so Gatekeeper refuses to open it while it is
  # quarantined.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-d", "-r", "com.apple.quarantine", "{{appdir}}/Looper.app"], must_succeed: false
    run "/usr/bin/xattr",
        args:         ["-d", "com.apple.quarantine", "{{staged_path}}/Looper-v#{version}/bin/looper"],
        must_succeed: false
  end

  uninstall quit: "com.mariovagomarzal.looper"

  zap trash: [
    "~/.config/looper",
    "~/.looper.toml",
  ]
end
