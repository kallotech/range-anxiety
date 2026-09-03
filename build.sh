#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h}"
app_path="$project_dir/build/RangeAnxiety.app"
staging_dir="$(mktemp -d /tmp/rangeanxiety-build.XXXXXX)"
staged_app="$staging_dir/RangeAnxiety.app"

cleanup() {
    if [[ "$staging_dir" == /tmp/rangeanxiety-build.* && -d "$staging_dir" ]]; then
        find "$staging_dir" -depth -delete
    fi
}
trap cleanup EXIT

cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"

mkdir -p "$staged_app/Contents/MacOS"
mkdir -p "$staged_app/Contents/Resources"

cp "$binary_dir/RangeAnxiety" "$staged_app/Contents/MacOS/RangeAnxiety"
cp "$project_dir/AppResources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/AppResources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"

xattr -cr "$staged_app"

signing_identity="${RANGE_ANXIETY_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"Range Anxiety Local Development"'; then
    signing_identity="Range Anxiety Local Development"
fi

if [[ -n "$signing_identity" ]]; then
    codesign --force --sign "$signing_identity" --timestamp=none "$staged_app"
else
    codesign --force --sign - "$staged_app"
    echo "Warning: no stable signing identity found; using an ad-hoc signature." >&2
fi

codesign --verify --deep --strict "$staged_app"

# Sign outside Desktop so its file provider cannot attach Finder metadata
# during signing, then copy the finished bundle into the project.
rm -rf "$app_path"
ditto --norsrc --noextattr "$staged_app" "$app_path"

echo "$app_path"
