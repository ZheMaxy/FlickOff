cask "flickoff" do
  version "1.2.0"
  sha256 "f7a85f83eee74b122ab4758d2310463fa55a960613be3421d9934595b4079e5a"

  url "https://github.com/ZheMaxy/FlickOff/releases/download/v1.2.0-beta.1/FlickOff-#{version}-arm64.zip"
  name "FlickOff"
  desc "Touch Bar brightness control and display off for Apple silicon MacBook Pro"
  homepage "https://github.com/ZheMaxy/FlickOff"

  livecheck do
    url "https://raw.githubusercontent.com/ZheMaxy/FlickOff/main/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "FlickOff.app"

  # FlickOff isn't notarized, which takes a paid Apple membership. Installing from this tap is
  # the choice to trust it, so the app opens without the Gatekeeper warning. Sparkle still checks
  # the Ed25519 signature of every update.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/FlickOff.app"]
  end

  uninstall quit: "io.github.ZheMaxy.FlickOff"

  zap trash: [
    "~/Library/Caches/io.github.ZheMaxy.FlickOff",
    "~/Library/HTTPStorages/io.github.ZheMaxy.FlickOff",
    "~/Library/Preferences/io.github.ZheMaxy.FlickOff.plist",
  ]
end
