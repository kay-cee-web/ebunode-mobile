#!/usr/bin/env bash
# Turns this repo into one customer's app, from the variables Ebunode sends with the Codemagic build.
#
#   bash scripts/configure.sh android|ios
#
# Required:  CLIENT_APP_NAME  CLIENT_APP_URL  CLIENT_BUNDLE_ID  CLIENT_APP_LOGO_URL
#            CLIENT_VERSION_CODE  CLIENT_VERSION_NAME
# Optional:  CLIENT_SPLASH_BG_COLOR (#FFFFFF)  CLIENT_SPLASH_LOGO_URL  CLIENT_SPLASH_TIMEOUT (3)
#            CLIENT_APPBAR_ENABLED (false)  CLIENT_APPBAR_COLOR (#5046E5)
# Android:   CLIENT_KEYSTORE_BASE64  CLIENT_KEYSTORE_PASSWORD  CLIENT_KEY_ALIAS   (the app's upload key)
set -euo pipefail

PLATFORM="${1:-android}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need() { [ -n "${!1:-}" ] || { echo "Missing $1 — Ebunode must send it with the build."; exit 1; }; }
for v in CLIENT_APP_NAME CLIENT_APP_URL CLIENT_BUNDLE_ID CLIENT_APP_LOGO_URL CLIENT_VERSION_CODE CLIENT_VERSION_NAME; do need "$v"; done

SPLASH_BG="${CLIENT_SPLASH_BG_COLOR:-#FFFFFF}"
APPBAR_ENABLED="${CLIENT_APPBAR_ENABLED:-false}"
APPBAR_COLOR="${CLIENT_APPBAR_COLOR:-#5046E5}"
SPLASH_TIMEOUT="${CLIENT_SPLASH_TIMEOUT:-3}"

echo "Configuring ${CLIENT_APP_NAME} (${CLIENT_BUNDLE_ID}) for ${PLATFORM}, version ${CLIENT_VERSION_NAME} (${CLIENT_VERSION_CODE})"

# ---- Images --------------------------------------------------------------
mkdir -p assets/build
curl -fsSL --retry 3 "$CLIENT_APP_LOGO_URL" -o assets/build/icon.png || { echo "Could not download the app icon from $CLIENT_APP_LOGO_URL"; exit 1; }
curl -fsSL --retry 3 "${CLIENT_SPLASH_LOGO_URL:-$CLIENT_APP_LOGO_URL}" -o assets/build/splash.png || cp assets/build/icon.png assets/build/splash.png

cat > flutter_launcher_icons.yaml <<YAML
flutter_launcher_icons:
  image_path: "assets/build/icon.png"
  android: true
  ios: true
  remove_alpha_ios: true
  background_color_ios: "${SPLASH_BG}"
  adaptive_icon_background: "${SPLASH_BG}"
  adaptive_icon_foreground: "assets/build/icon.png"
  adaptive_icon_foreground_inset: 20
  min_sdk_android: 21
YAML

cat > flutter_native_splash.yaml <<YAML
flutter_native_splash:
  color: "${SPLASH_BG}"
  image: "assets/build/splash.png"
  android_12:
    color: "${SPLASH_BG}"
    image: "assets/build/splash.png"
  fullscreen: false
YAML

# ---- What the app loads (read by lib/main.dart) ---------------------------
export APPBAR_ENABLED APPBAR_COLOR SPLASH_TIMEOUT
python3 - <<'PY'
import json, os
json.dump({
    "APP_URL": os.environ["CLIENT_APP_URL"],
    "APP_NAME": os.environ["CLIENT_APP_NAME"],
    "APPBAR_ENABLED": os.environ["APPBAR_ENABLED"],
    "APPBAR_COLOR": os.environ["APPBAR_COLOR"],
    "SPLASH_TIMEOUT": os.environ["SPLASH_TIMEOUT"],
}, open("build_config.json", "w"))
PY

# ---- Platform ------------------------------------------------------------
if [ "$PLATFORM" = "android" ]; then
  # applicationId and the app name are read from CLIENT_BUNDLE_ID / CLIENT_APP_NAME by android/app/build.gradle.kts
  if [ -n "${CLIENT_KEYSTORE_BASE64:-}" ]; then
    need CLIENT_KEYSTORE_PASSWORD; need CLIENT_KEY_ALIAS
    printf '%s' "$CLIENT_KEYSTORE_BASE64" | base64 --decode > android/app/upload.p12
    cat > android/key.properties <<PROPS
storeFile=upload.p12
storePassword=${CLIENT_KEYSTORE_PASSWORD}
keyAlias=${CLIENT_KEY_ALIAS}
keyPassword=${CLIENT_KEYSTORE_PASSWORD}
storeType=pkcs12
PROPS
    echo "Upload key installed."
  else
    echo "No upload key sent — the build is signed with a debug key and can't go to Google Play."
  fi
else
  # Bundle id and the name under the icon
  sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = com.ebunode.ebunodeMobile;/PRODUCT_BUNDLE_IDENTIFIER = ${CLIENT_BUNDLE_ID};/g" ios/Runner.xcodeproj/project.pbxproj
  plutil -replace CFBundleDisplayName -string "$CLIENT_APP_NAME" ios/Runner/Info.plist
  plutil -replace CFBundleName -string "${CLIENT_APP_NAME:0:15}" ios/Runner/Info.plist
fi

echo "Done."
