#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: scripts/release.sh <version>" >&2
    exit 2
fi
if [[ -z "${RANGE_ANXIETY_SIGNING_IDENTITY:-}" || "$RANGE_ANXIETY_SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "RANGE_ANXIETY_SIGNING_IDENTITY must name a Developer ID Application certificate." >&2
    exit 2
fi

dist_dir="$project_dir/dist"
work_dir="$(mktemp -d /tmp/rangeanxiety-release.XXXXXX)"
cleanup() {
    if [[ "$work_dir" == /tmp/rangeanxiety-release.* && -d "$work_dir" ]]; then
        find "$work_dir" -depth -delete
    fi
}
trap cleanup EXIT

rm -rf "$dist_dir"
mkdir -p "$dist_dir" "$work_dir/image"
RANGE_ANXIETY_UNIVERSAL=1 RANGE_ANXIETY_APP_OUTPUT="$work_dir/RangeAnxiety.app" "$project_dir/build.sh"

ditto --norsrc --noextattr "$work_dir/RangeAnxiety.app" "$work_dir/image/RangeAnxiety.app"
ln -s /Applications "$work_dir/image/Applications"
hdiutil create -quiet -volname "RangeAnxiety" -srcfolder "$work_dir/image" -format UDZO "$dist_dir/RangeAnxiety-$version.dmg"

if [[ -n "${RANGE_ANXIETY_NOTARY_KEY_PATH:-}" && -n "${RANGE_ANXIETY_NOTARY_KEY_ID:-}" && -n "${RANGE_ANXIETY_NOTARY_ISSUER_ID:-}" ]]; then
    xcrun notarytool submit "$dist_dir/RangeAnxiety-$version.dmg" --wait \
        --key "$RANGE_ANXIETY_NOTARY_KEY_PATH" \
        --key-id "$RANGE_ANXIETY_NOTARY_KEY_ID" \
        --issuer "$RANGE_ANXIETY_NOTARY_ISSUER_ID"
elif [[ -n "${RANGE_ANXIETY_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dist_dir/RangeAnxiety-$version.dmg" --wait --keychain-profile "$RANGE_ANXIETY_NOTARY_PROFILE"
else
    echo "Set App Store Connect API-key variables or RANGE_ANXIETY_NOTARY_PROFILE." >&2
    exit 2
fi

xcrun stapler staple "$dist_dir/RangeAnxiety-$version.dmg"
xcrun stapler validate "$dist_dir/RangeAnxiety-$version.dmg"
spctl --assess --type open --context context:primary-signature -vv "$dist_dir/RangeAnxiety-$version.dmg"
shasum -a 256 "$dist_dir/RangeAnxiety-$version.dmg" > "$dist_dir/RangeAnxiety-$version.dmg.sha256"

echo "$dist_dir/RangeAnxiety-$version.dmg"
