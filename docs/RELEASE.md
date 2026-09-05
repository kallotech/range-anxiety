# Release process

RangeAnxiety releases are Developer ID signed, notarised by Apple, stapled, and then signed again at the update-archive level by Sparkle. Do not put certificate exports, App Store Connect keys, notarisation credentials, or the Sparkle private key in the repository or an issue.

## Required accounts and keys

- Active Apple Developer Program membership.
- A `Developer ID Application` certificate exported as a password-protected PKCS#12 file for CI.
- An App Store Connect API key allowed to submit to Apple's notary service.
- The RangeAnxiety Sparkle private key. Its public key is already embedded in `AppResources/Info.plist`.
- A GitHub environment or repository configuration containing the release secrets named in `.github/workflows/release.yml`.

The Sparkle private key is currently stored in the local login Keychain under account `io.github.kallotech.rangeanxiety`. Export it only when preparing the encrypted GitHub secret:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.github.kallotech.rangeanxiety \
  -x /a/private/location/range-anxiety-sparkle-private-key
```

Delete the exported file securely after adding its contents to the `SPARKLE_PRIVATE_KEY` GitHub secret. The Keychain copy remains the source of truth.

## Local release candidate

Store notarisation credentials in Keychain with `notarytool store-credentials`, then run:

```sh
export RANGE_ANXIETY_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export RANGE_ANXIETY_NOTARY_PROFILE="range-anxiety-notary"
scripts/release.sh 0.7.0
```

The script refuses ad-hoc or local-development identities. It creates `dist/RangeAnxiety-<version>.dmg`, submits it to Apple, staples the ticket, assesses the result with Gatekeeper, and writes a SHA-256 file.

## GitHub release

1. Update `CFBundleShortVersionString` and `CFBundleVersion`.
2. Update `CHANGELOG.md` and the Homebrew cask template.
3. Merge the tested release commit.
4. Tag it as `v<version>` and push the tag.
5. The Release workflow validates the tag, builds, signs, notarises, creates the Sparkle appcast, and publishes the GitHub release.

The app reads `appcast.xml` from the latest GitHub release. Sparkle verifies the EdDSA signature and macOS verifies the Developer ID signature.

## Homebrew

Copy `packaging/homebrew/range-anxiety.rb` into `Casks/range-anxiety.rb` in the public `kallotech/homebrew-tap` repository. Replace the checksum placeholder with the SHA-256 emitted for the notarised DMG. Validate it with:

```sh
brew audit --cask --strict kallotech/tap/range-anxiety
brew install --cask kallotech/tap/range-anxiety
```

The cask installs the app and exposes the bundled `ra` launcher. Do not publish the cask until its referenced signed release exists.
