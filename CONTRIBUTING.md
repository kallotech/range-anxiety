# Contributing

Thanks for helping improve RangeAnxiety.

## Development setup

- macOS 13 or later
- Swift 5.9 or later
- Full Xcode for XCTest, or Apple command-line tools for ordinary builds

Build the app bundle:

```sh
./build.sh
```

Run the test suite with full Xcode selected:

```sh
swift test
```

When XCTest is unavailable, the standalone parser check can be compiled with the command documented in `Tests/ParserSmoke/main.swift`.

## Pull requests

- Keep changes focused and explain their user-visible effect.
- Add or update response fixtures when changing a provider parser.
- Never commit real API keys, credentials, usage exports, or account identifiers.
- New connectors must use a provider-supported usage or billing API. Do not estimate account-wide totals from inference requests.
- Preserve Reduce Motion behavior for animation changes.

By contributing, you agree that your contribution may be distributed under the MIT License.
