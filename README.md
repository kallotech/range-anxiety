
# RangeAnxiety

A small native macOS menu-bar app for viewing usage reported by connected AI providers.

<img width="1252" height="781" alt="Screenshot 2026-09-01 at 2 33 44 pm" src="https://github.com/user-attachments/assets/1d38ec37-9b8a-471f-bd57-0c5f0c81bd77" />

> Early public preview. This is an independent, unofficial project. It is not affiliated with, endorsed by, or sponsored by OpenAI or any other provider named in the app.

The current public preview is source-only. The signed DMG, automatic-update feed, and Homebrew cask are prepared but will not be published until Developer ID signing and Apple notarization credentials are configured.

## Features

- Combined **today** totals for providers that expose genuine daily tokens or spend.
- Separate, draggable cards for every connected provider.
- Codex quota windows, reset times, and burn-rate-aware progress animations.
- Claude Code 5-hour and 7-day subscription limits through an opt-in, credential-free status-line capture.
- Clear labels for month-to-date, through-yesterday, and recent-rate metrics.
- Centralized provider and display settings.
- Support for the macOS Reduce Motion accessibility setting.
- Isolated, named Codex account profiles with provider-owned browser sign-in.
- Manual account activation for new sessions through the bundled `ra` launcher.
- Codex and Claude CLI installation, version, authentication health, and update guidance.
- Launch-at-login support and signed Sparkle update integration.

## Provider connectors

| Provider | Reported data | Requirement |
| --- | --- | --- |
| Codex | Quota windows and reset times | A local Codex or ChatGPT installation and login |
| Claude Code | 5-hour and 7-day subscription windows | Claude Code 2.1.80+ with limit capture enabled in Settings |
| OpenRouter | Daily tokens and spend | Management key |
| OpenAI API | Daily organization tokens and cost | Organization Admin API key |
| Anthropic | Daily organization tokens and cost | Admin API key |
| xAI | Month-to-date team spend | Management key and Team ID |
| Mistral AI | Month-to-date usage | Admin API key |
| Together AI | Month-to-date spend through yesterday | API key |
| Fireworks AI | Month-to-date account spend | API key and Account ID |
| GroqCloud | Current five-minute token rate | Enterprise metrics access |

Google Gemini, DeepSeek, and Azure OpenAI appear in Settings with their current reporting limitations. The app does not invent account-wide totals when a provider does not expose a suitable reporting API.

## Privacy and credentials

- The app has no analytics or telemetry of its own.
- The default Codex connector uses the existing local Codex-managed login. Optional managed accounts use isolated profile folders, while Codex owns the browser login, token storage, and token refresh inside each profile.
- Claude Code limit capture receives the documented `rate_limits` status-line fields and stores only percentages, reset times, and capture time. It does not read Claude OAuth credentials or make Anthropic API calls.
- Other provider credentials are sent only to the selected provider's reporting endpoint.
- Provider credentials are stored encrypted in macOS Keychain and are never included in the app bundle or repository.
- Existing owner-only credential files from earlier prototypes are migrated into Keychain, verified, and removed automatically.
- Background refreshes cannot open a Keychain password dialog. An ad-hoc rebuild whose identity changes instead asks the user to reconnect from Settings; Developer ID-signed releases retain a stable identity.

Support development through [Buy Me a Coffee](https://buymeacoffee.com/kallotech).

Never include credentials or personal usage exports in bug reports.

## Build from source

Requirements:

- Xcode 16.2 or later, or the matching command-line tools (Swift 6 and a macOS 15.2 SDK or newer)
- A macOS version supported by those build tools

The built app still supports macOS 13 or later. The newer SDK is needed to compile the Settings-opening API; it does not raise the app's minimum macOS version. CI uses Xcode 16.2 on macOS 14.

If the Apple command-line tools are not installed yet:

```sh
xcode-select --install
```

Clone, build, and install RangeAnxiety for the current user:

```sh
git clone https://github.com/kallotech/range-anxiety.git
cd range-anxiety
./build.sh
mkdir -p "$HOME/Applications"
ditto "build/RangeAnxiety.app" "$HOME/Applications/RangeAnxiety.app"
open "$HOME/Applications/RangeAnxiety.app"
```

RangeAnxiety then appears in the menu bar. Open its Settings to connect providers, add named Codex accounts, or enable launch at login.

To show Claude subscription limits, open **Settings → Providers → Claude Code** and enable **Capture limits from Claude Code**. Send at least one message in a signed-in Claude Pro or Max session; Claude supplies the 5-hour and 7-day figures after a response. If you already use a custom Claude status line, RangeAnxiety chains it and preserves its output. Disabling capture restores the previous configuration.

Local builds use the configured code-signing identity and otherwise fall back to an ad-hoc signature. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** for RangeAnxiety. Public binary releases should be Developer ID signed, hardened, and notarized.

The built app contains an optional `ra` launcher. Until the Homebrew release is available, source installs can run it directly:

```sh
"$HOME/Applications/RangeAnxiety.app/Contents/Resources/ra" list
"$HOME/Applications/RangeAnxiety.app/Contents/Resources/ra" codex
```

`ra list` shows the managed profiles and `ra codex` starts a new Codex session with the account marked active in RangeAnxiety. The user's normal CLI profile is never rewritten. Claude health checks are available, but managed Claude account switching remains disabled until its macOS Keychain credentials can be isolated safely.

Release maintainers should follow [docs/RELEASE.md](docs/RELEASE.md).

Maintainers can set `RANGE_ANXIETY_SIGNING_IDENTITY` to a code-signing identity name. A stable signing identity prevents macOS from treating each changed local build as a different app for Keychain access.

## Tests

With full Xcode selected:

```sh
swift test
```

The standalone parser check in `Tests/ParserSmoke/main.swift` works on Macs with command-line tools only.

The Settings-window checks also work without XCTest:

```sh
swiftc -parse-as-library Sources/RangeAnxiety/SettingsWindowPresenter.swift Tests/SettingsWindowSmoke/main.swift -o /tmp/rangeanxiety-settings-window-smoke
/tmp/rangeanxiety-settings-window-smoke
```

## App icon

The supplied artwork is preserved in `AppResources/AppIcon.svg`. The build script bundles `AppResources/AppIcon.icns`; to regenerate its standard and Retina sizes on macOS:

```sh
swift scripts/generate-app-icon.swift AppResources/AppIcon.svg build/AppIcon.iconset
iconutil --convert icns build/AppIcon.iconset --output AppResources/AppIcon.icns
```

## Version history

See [CHANGELOG.md](CHANGELOG.md). Public Git history and GitHub Releases begin with `v0.6.0`; earlier prototypes are documented retrospectively because exact source snapshots were not preserved.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

Codex, OpenAI, Anthropic, OpenRouter, xAI, Mistral, Together AI, Fireworks AI, Groq, Google Gemini, DeepSeek, Azure, and other product names are trademarks of their respective owners.
