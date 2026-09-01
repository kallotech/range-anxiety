# RangeAnxiety

A small native macOS menu-bar app for viewing usage reported by connected AI providers.

> Early public preview. This is an independent, unofficial project. It is not affiliated with, endorsed by, or sponsored by OpenAI or any other provider named in the app.

The first public release is source-only. Downloadable binaries will follow after Developer ID signing and Apple notarization are configured.

## Features

- Combined **today** totals for providers that expose genuine daily tokens or spend.
- Separate, draggable cards for every connected provider.
- Codex quota windows, reset times, and burn-rate-aware progress animations.
- Clear labels for month-to-date, through-yesterday, and recent-rate metrics.
- Centralized provider and display settings.
- Support for the macOS Reduce Motion accessibility setting.

## Provider connectors

| Provider | Reported data | Requirement |
| --- | --- | --- |
| Codex | Quota windows and reset times | A local Codex or ChatGPT installation and login |
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
- Codex uses the existing local Codex-managed login; this app does not request or store Codex login details.
- Other provider credentials are sent only to the selected provider's reporting endpoint.
- Provider credentials are stored encrypted in macOS Keychain and are never included in the app bundle or repository.
- Existing owner-only credential files from earlier prototypes are migrated into Keychain, verified, and removed automatically.
- Background refreshes cannot open a Keychain password dialog. An ad-hoc rebuild whose identity changes instead asks the user to reconnect from Settings; Developer ID-signed releases retain a stable identity.

Support development through [Buy Me a Coffee](https://buymeacoffee.com/kallotech).

Never include credentials or personal usage exports in bug reports.

## Build from source

Requirements:

- macOS 13 or later
- Swift 5.9 or later
- Xcode command-line tools

```sh
./build.sh
open "build/RangeAnxiety.app"
```

Local builds use the configured code-signing identity and otherwise fall back to an ad-hoc signature. Gatekeeper may reject a downloaded ad-hoc build from another Mac. Public binary releases should be Developer ID signed, hardened, and notarized.

Maintainers can set `RANGE_ANXIETY_SIGNING_IDENTITY` to a code-signing identity name. A stable signing identity prevents macOS from treating each changed local build as a different app for Keychain access.

## Tests

With full Xcode selected:

```sh
swift test
```

The standalone parser check in `Tests/ParserSmoke/main.swift` works on Macs with command-line tools only.

## Version history

See [CHANGELOG.md](CHANGELOG.md). Public Git history and GitHub Releases begin with `v0.6.0`; earlier prototypes are documented retrospectively because exact source snapshots were not preserved.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

Codex, OpenAI, Anthropic, OpenRouter, xAI, Mistral, Together AI, Fireworks AI, Groq, Google Gemini, DeepSeek, Azure, and other product names are trademarks of their respective owners.
