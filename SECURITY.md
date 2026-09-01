# Security policy

## Supported versions

Security fixes are provided for the latest published version.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not include API keys, credentials, personal usage data, or other secrets in a public issue.

If private reporting is unavailable, open a public issue containing only a request for a private contact channel and no vulnerability details.

## Credential storage

Provider credentials are encrypted by macOS Keychain. They are not committed to this repository or included in app bundles. Earlier owner-only credential files are removed only after the app has written the credential to Keychain and verified that it can read the same value back.

Background refreshes explicitly prohibit authentication UI, preventing a stale Keychain access rule from producing repeated password prompts. A changed ad-hoc signing identity is reported inside Settings and requires an intentional reconnect. Public binary releases should use a stable Developer ID signature.
