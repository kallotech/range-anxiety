cask "range-anxiety" do
  version "0.7.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/kallotech/range-anxiety/releases/download/v#{version}/RangeAnxiety-#{version}.dmg"
  name "RangeAnxiety"
  desc "Local-first AI provider usage and coding-account capacity monitor"
  homepage "https://github.com/kallotech/range-anxiety"

  depends_on macos: ">= :ventura"

  app "RangeAnxiety.app"
  binary "#{appdir}/RangeAnxiety.app/Contents/Resources/ra"

  zap trash: [
    "~/Library/Application Support/RangeAnxiety",
    "~/Library/Preferences/io.github.kallotech.rangeanxiety.plist",
  ]
end
