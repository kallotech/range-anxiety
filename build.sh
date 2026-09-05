#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h}"
app_path="${RANGE_ANXIETY_APP_OUTPUT:-$project_dir/build/RangeAnxiety.app}"
staging_dir="$(mktemp -d /tmp/rangeanxiety-build.XXXXXX)"
staged_app="$staging_dir/RangeAnxiety.app"

cleanup() {
    if [[ "$staging_dir" == /tmp/rangeanxiety-build.* && -d "$staging_dir" ]]; then
        find "$staging_dir" -depth -delete
    fi
}
trap cleanup EXIT

cd "$project_dir"
build_arguments=(-c release)
if [[ "${RANGE_ANXIETY_UNIVERSAL:-0}" == "1" ]]; then
    build_arguments+=(--arch arm64 --arch x86_64)
fi
swift build "${build_arguments[@]}"
binary_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"

mkdir -p "$staged_app/Contents/MacOS"
mkdir -p "$staged_app/Contents/Resources"
mkdir -p "$staged_app/Contents/Frameworks"

cp "$binary_dir/RangeAnxiety" "$staged_app/Contents/MacOS/RangeAnxiety"
cp "$binary_dir/ra" "$staged_app/Contents/Resources/ra"
cp "$project_dir/AppResources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/AppResources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
ditto --norsrc --noextattr "$binary_dir/Sparkle.framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
chmod 755 "$staged_app/Contents/MacOS/RangeAnxiety" "$staged_app/Contents/Resources/ra"

if [[ "${RANGE_ANXIETY_UNIVERSAL:-0}" == "1" ]]; then
    lipo -verify_arch arm64 x86_64 "$staged_app/Contents/MacOS/RangeAnxiety"
    lipo -verify_arch arm64 x86_64 "$staged_app/Contents/Resources/ra"
fi

xattr -cr "$staged_app"

signing_identity="${RANGE_ANXIETY_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"Range Anxiety Local Development"'; then
    signing_identity="Range Anxiety Local Development"
fi

if [[ -n "$signing_identity" ]]; then
    if [[ "$signing_identity" == Developer\ ID\ Application:* ]]; then
        codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$staged_app"
    else
        codesign --force --deep --sign "$signing_identity" --timestamp=none "$staged_app"
    fi
else
    codesign --force --deep --sign - "$staged_app"
    echo "Warning: no stable signing identity found; using an ad-hoc signature." >&2
fi

codesign --verify --deep --strict "$staged_app"

# Sign outside Desktop so its file provider cannot attach Finder metadata
# during signing, then copy the finished bundle into the project.
mkdir -p "${app_path:h}"
rm -rf "$app_path"
ditto --norsrc --noextattr "$staged_app" "$app_path"
xattr -cr "$app_path"
codesign --verify --deep --strict "$app_path"

if [[ -z "${RANGE_ANXIETY_APP_OUTPUT:-}" ]]; then
    archive_path="$project_dir/build/RangeAnxiety.app.zip"
    rm -f "$archive_path"
    ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$archive_path"
fi

echo "$app_path"
