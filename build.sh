#!/bin/bash
set -euo pipefail

# Build script for ClaudeHealth using xcodebuild + the generated Xcode project.
#
# Usage:
#   ./build.sh                 # Debug build (Apple Development signing) → build/
#   ./build.sh --run           # Debug build + launch
#   ./build.sh --install       # Release build + copy to /Applications
#   ./build.sh --release       # Release build (no install)
#   ./build.sh --notarize      # Release + Developer ID + notarize + staple
#   ./build.sh --dmg           # Release + notarize app + create signed/notarized/stapled .dmg
#
# Override signing via env vars:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh --release
#   DEV_TEAM=PDPT7GQQWN ./build.sh
#
# Notarization requires (set as env vars or in keychain via `xcrun notarytool store-credentials`):
#   NOTARY_PROFILE       (a stored notarytool profile name — preferred)
#   …or…
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD  (app-specific password)

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="ClaudeHealth"
SCHEME="ClaudeHealth"
PROJECT="$APP_NAME.xcodeproj"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
TEAM_ID="PDPT7GQQWN"

mkdir -p "$BUILD_DIR"

# Team-pinned Designated Requirement (Wardle / W5):
# Pins to subject.OU (= Team ID) instead of the per-cert Common Name, so the DR
# survives Apple Development cert renewals. Accepts either Apple Development
# (1.2.840.113635.100.6.1.12) or Developer ID Application (1.2.840.113635.100.6.1.13)
# from our team — but no other team and no Distribution / Mac App Store certs.
DR_FILE="$BUILD_DIR/designated-requirement.txt"
cat > "$DR_FILE" <<EOF
designated => identifier "com.max.$APP_NAME" and anchor apple generic and certificate leaf[subject.OU] = "$TEAM_ID" and (certificate leaf[field.1.2.840.113635.100.6.1.12] /* Apple Development */ or certificate leaf[field.1.2.840.113635.100.6.1.13] /* Developer ID Application */)
EOF

# Regenerate Xcode project if project.yml is newer
if command -v xcodegen >/dev/null 2>&1 && [[ -f project.yml ]]; then
    if [[ ! -d "$PROJECT" || project.yml -nt "$PROJECT/project.pbxproj" ]]; then
        echo "→ Regenerating Xcode project from project.yml…"
        xcodegen >/dev/null
    fi
fi

ACTION="${1:---debug}"

case "$ACTION" in
    --release|--install|--notarize|--dmg)
        CONFIG=Release
        ;;
    *)
        CONFIG=Debug
        ;;
esac

# Apply signing override if provided via env
SIGN_OVERRIDE=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    SIGN_OVERRIDE+=("CODE_SIGN_IDENTITY=$SIGN_IDENTITY")
fi
if [[ -n "${DEV_TEAM:-}" ]]; then
    SIGN_OVERRIDE+=("DEVELOPMENT_TEAM=$DEV_TEAM")
fi

echo "→ Building $APP_NAME ($CONFIG)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ${SIGN_OVERRIDE[@]+"${SIGN_OVERRIDE[@]}"} \
    build 2>&1 | grep -E "(error:|warning:|Compiling|Linking|CodeSign|Signing Identity|BUILD)" | tail -40 || true

PRODUCT="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
if [[ ! -d "$PRODUCT" ]]; then
    echo "✗ Build product not found at $PRODUCT"
    exit 1
fi

# Copy to build/ for convenience
rm -rf "$BUILD_DIR/$APP_NAME.app"
cp -R "$PRODUCT" "$BUILD_DIR/$APP_NAME.app"
APP="$BUILD_DIR/$APP_NAME.app"

# Resolve the re-sign identity. Order of precedence:
#   1. SIGN_IDENTITY env var, if set
#   2. Author's Apple Development cert, if present in keychain
#   3. Ad-hoc ("-") — Gatekeeper warning on first launch but works for personal use
RESIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$RESIGN_IDENTITY" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development: Max Polwin (QXT62Q4V34)"; then
        RESIGN_IDENTITY="Apple Development: Max Polwin (QXT62Q4V34)"
    else
        echo "  (no SIGN_IDENTITY env, no author cert in keychain → falling back to ad-hoc signing)"
        echo "  (set SIGN_IDENTITY=\"Apple Development: Your Name (TEAMID)\" to sign with your own cert)"
        RESIGN_IDENTITY="-"
    fi
fi
echo "→ Re-signing with team-pinned Designated Requirement…"
codesign --force --options runtime \
    --sign "$RESIGN_IDENTITY" \
    --entitlements Resources/ClaudeHealth.entitlements \
    --requirements "$DR_FILE" \
    "$APP" 2>&1 | sed 's/^/  /' || true

echo "✓ Built: $APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "(Authority|Identifier|TeamIdentifier|Format|Signature)" | head -8

# --- Action-specific tail ---

if [[ "$ACTION" == "--run" ]]; then
    echo "→ Launching…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi

if [[ "$ACTION" == "--install" ]]; then
    echo "→ Installing to /Applications…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    # Re-sign at the new location with the pinned DR (same as above so designated
    # requirement matches in /Applications too).
    codesign --force --options runtime \
        --sign "$RESIGN_IDENTITY" \
        --entitlements Resources/ClaudeHealth.entitlements \
        --requirements "$DR_FILE" \
        "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "✓ Installed: /Applications/$APP_NAME.app"
    echo ""
    echo "Launch:  open /Applications/$APP_NAME.app"

    # Tamper-detection helpers (W13 of v1.3 plan): SHA256 of binary + bundled icons.
    CHECKSUMS="$BUILD_DIR/checksums.txt"
    {
        echo "# ClaudeHealth bundle integrity baseline — $(date)"
        shasum -a 256 "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
        find "/Applications/$APP_NAME.app/Contents/Resources" -name "*.icns" -exec shasum -a 256 {} \;
    } > "$CHECKSUMS"
    echo "  Wrote $CHECKSUMS — diff against this after future installs to detect tampering."
fi

if [[ "$ACTION" == "--notarize" ]]; then
    if [[ "${SIGN_IDENTITY:-}" != *"Developer ID Application"* ]]; then
        echo ""
        echo "✗ Notarization requires SIGN_IDENTITY to be a Developer ID Application cert."
        echo "  Example:"
        echo '    SIGN_IDENTITY="Developer ID Application: Max Polwin (PDPT7GQQWN)" ./build.sh --notarize'
        echo ""
        echo "  You don't appear to have a Developer ID Application cert yet. Create one:"
        echo "    https://developer.apple.com/account/resources/certificates/add"
        echo "    → 'Developer ID Application' → upload CSR → download → double-click."
        exit 1
    fi

    ZIP="$BUILD_DIR/$APP_NAME.zip"
    echo "→ Creating notarization zip…"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

    echo "→ Submitting to notary service (this can take 1–10 min)…"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
        xcrun notarytool submit "$ZIP" \
            --apple-id "$NOTARY_APPLE_ID" \
            --team-id "$NOTARY_TEAM_ID" \
            --password "$NOTARY_PASSWORD" \
            --wait
    else
        echo "✗ Set NOTARY_PROFILE (recommended) or NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD"
        echo "  To create a profile (one-time):"
        echo "    xcrun notarytool store-credentials ClaudeHealthNotary --apple-id 'you@example.com' --team-id $TEAM_ID"
        exit 1
    fi

    echo "→ Stapling ticket…"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP" && echo "✓ Notarized & stapled"
fi

if [[ "$ACTION" == "--dmg" ]]; then
    if [[ "${SIGN_IDENTITY:-}" != *"Developer ID Application"* ]]; then
        echo ""
        echo "✗ DMG requires SIGN_IDENTITY = Developer ID Application cert."
        echo "  SIGN_IDENTITY=\"Developer ID Application: Max Polwin (PDPT7GQQWN)\" \\"
        echo "  NOTARY_PROFILE=ClaudeHealthNotary \\"
        echo "      ./build.sh --dmg"
        exit 1
    fi
    if [[ -z "${NOTARY_PROFILE:-}" && -z "${NOTARY_APPLE_ID:-}" ]]; then
        echo "✗ DMG step needs NOTARY_PROFILE (or NOTARY_APPLE_ID/TEAM_ID/PASSWORD)."
        exit 1
    fi

    # 1. Notarize + staple the .app first (DMG can be notarized too, but a stapled
    #    .app inside an unstapled DMG also works on Gatekeeper). Belt + suspenders:
    #    we staple both.
    echo "→ Notarizing the .app inside the DMG-to-be…"
    APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
    rm -f "$APP_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$APP_ZIP"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$APP_ZIP" \
            --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    fi
    xcrun stapler staple "$APP"

    # 2. Stage a directory with the .app + a symlink to /Applications (drag target)
    STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    # 3. Build the DMG
    DMG="$BUILD_DIR/$APP_NAME.dmg"
    rm -f "$DMG"
    echo "→ Creating $DMG…"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG" >/dev/null

    # 4. Sign the DMG itself
    echo "→ Signing DMG with Developer ID…"
    codesign --force --sign "$RESIGN_IDENTITY" --timestamp "$DMG"

    # 5. Notarize the DMG, then staple the ticket so offline-Gatekeeper passes too
    echo "→ Notarizing DMG…"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$DMG" \
            --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    fi
    echo "→ Stapling DMG ticket…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG" && echo "✓ DMG notarized & stapled"

    # 6. Final user-facing verification
    echo ""
    echo "Final checks:"
    spctl -a -vv -t install "$DMG" 2>&1 | sed 's/^/  /'
    echo ""
    echo "✓ Distributable DMG: $DMG"
    echo "  Drop on AirDrop / share via any channel — opens cleanly on any Mac."
fi
