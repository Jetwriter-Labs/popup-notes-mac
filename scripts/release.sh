#!/bin/zsh
# Build, sign, package, and (optionally) notarize PopupNotes for distribution.
#
# Usage:
#   ./scripts/release.sh                # dev-signed DMG — quick sharing; recipients see a Gatekeeper warning
#   ./scripts/release.sh developer-id   # Developer ID DMG; also notarizes + staples when NOTARY_PROFILE is set
#   ./scripts/release.sh app-store      # signed .pkg ready to upload to App Store Connect
#
# One-time notarization setup (paid Apple Developer Program required):
#   xcrun notarytool store-credentials notary \
#     --apple-id <your-apple-id> --team-id 422R4JTNFH
#   (use an app-specific password from account.apple.com)
# Then:
#   NOTARY_PROFILE=notary ./scripts/release.sh developer-id
#
# See docs/RELEASING.md for the full walkthrough.

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-dev}"
PROJECT=PopupNotes/PopupNotes.xcodeproj
SCHEME=PopupNotes
ARCHIVE=build/PopupNotes.xcarchive

echo "▸ Archiving $SCHEME (Release)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    archive -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")
mkdir -p dist

make_dmg() { # $1 = path to .app, $2 = output dmg
    local staging=build/dmg-staging
    rm -rf "$staging" && mkdir -p "$staging"
    cp -R "$1" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "Popup Notes" -srcfolder "$staging" -ov -format UDZO "$2" >/dev/null
    echo "▸ Created $2"
}

case "$MODE" in
dev)
    cp -R "$ARCHIVE/Products/Applications/$SCHEME.app" dist/
    make_dmg "dist/$SCHEME.app" "dist/$SCHEME-$VERSION.dmg"
    echo "⚠ Dev-signed only: recipients must approve it in System Settings ▸ Privacy & Security."
    ;;
developer-id)
    echo "▸ Exporting with Developer ID…"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" \
        -exportOptionsPlist scripts/export-developer-id.plist \
        -exportPath dist/export -allowProvisioningUpdates -quiet
    make_dmg "dist/export/$SCHEME.app" "dist/$SCHEME-$VERSION.dmg"
    # Sign the DMG container itself, not just the app inside — Gatekeeper's
    # primary-signature assessment rejects unsigned images.
    codesign --force --sign "Developer ID Application" --timestamp "dist/$SCHEME-$VERSION.dmg"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "▸ Notarizing (waits for Apple — typically a few minutes)…"
        xcrun notarytool submit "dist/$SCHEME-$VERSION.dmg" \
            --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "dist/$SCHEME-$VERSION.dmg"
        spctl --assess --type open --context context:primary-signature \
            -v "dist/$SCHEME-$VERSION.dmg" && echo "✓ Notarized and stapled — share away."
    else
        echo "⚠ Skipped notarization (NOTARY_PROFILE not set) — Gatekeeper will block recipients."
    fi
    ;;
app-store)
    echo "▸ Exporting signed .pkg for App Store Connect…"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" \
        -exportOptionsPlist scripts/export-app-store.plist \
        -exportPath dist/appstore -allowProvisioningUpdates -quiet
    ls -lh dist/appstore/
    echo "▸ Upload the .pkg with the Transporter app (or Xcode ▸ Organizer ▸ Distribute)."
    ;;
*)
    echo "usage: $0 [dev|developer-id|app-store]" >&2
    exit 64
    ;;
esac
