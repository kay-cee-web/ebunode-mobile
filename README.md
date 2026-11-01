# Ebunode Mobile

One Flutter app that becomes every customer's Android and iOS app. It opens the customer's published
Ebunode app (`https://<app>.ebunode.app` or their custom domain) full screen, with their name, icon,
splash screen and optional app bar.

Ebunode's API starts builds on Codemagic with the customer's settings as `CLIENT_*` variables.
Nothing here is edited per customer.

## What the app does

- Loads the app's address; its own pages and subdomains stay in the app, other sites, `mailto:`, `tel:`,
  maps and app-store links open outside.
- Google sign-in and Stripe / PayPal checkout pages open inside so their redirects come back.
- File uploads (`<input type="file">`) on Android and iOS.
- Back button / swipe goes back in the page history.
- Progress bar while loading, an offline screen with "Try again", and the splash stays until the first page loads.

## Codemagic workflows (`codemagic.yaml`)

| Workflow | Output | Store |
| --- | --- | --- |
| `ebunode-android` | signed `.aab` + `.apk` | Ebunode uploads the `.aab` to Google Play through the Play Developer API |
| `ebunode-ios` | signed `.ipa` | uploaded to the customer's App Store Connect when `CLIENT_IOS_RELEASE` is `testflight` or `app_store` |

`scripts/configure.sh` turns the repo into one customer's app at the start of every build:
downloads the icon and splash image, writes the icon / splash configs, the bundle id and app name,
and installs the Android upload key Ebunode keeps for that app.

### Variables Ebunode sends

| Variable | Example |
| --- | --- |
| `CLIENT_APP_NAME` | Glow Salon |
| `CLIENT_APP_URL` | https://glow-salon.ebunode.app |
| `CLIENT_BUNDLE_ID` | com.glowsalon.app |
| `CLIENT_APP_LOGO_URL` / `CLIENT_SPLASH_LOGO_URL` | https://… (PNG, 1024×1024) |
| `CLIENT_SPLASH_BG_COLOR`, `CLIENT_SPLASH_TIMEOUT` | #FFFFFF, 3 |
| `CLIENT_APPBAR_ENABLED`, `CLIENT_APPBAR_COLOR` | true, #5046E5 |
| `CLIENT_VERSION_CODE`, `CLIENT_VERSION_NAME` | 7, 1.2.0 |
| `CLIENT_KEYSTORE_BASE64`, `CLIENT_KEYSTORE_PASSWORD`, `CLIENT_KEY_ALIAS` | Android upload key (PKCS12) |
| `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY` | the customer's App Store Connect API key |
| `CERTIFICATE_PRIVATE_KEY` | RSA key Ebunode keeps per Apple account, so every build reuses one distribution certificate |
| `CLIENT_IOS_RELEASE` | none · testflight · app_store |

## Setting up Codemagic (once)

1. Add this repository as an app in Codemagic and choose **codemagic.yaml** as the configuration.
2. Copy the app id from the app's address (`https://codemagic.io/app/<app id>`).
3. Teams → Personal account → Integrations → **Codemagic API** → copy the API token.
4. App settings → **Webhooks** → add
   `https://api.ebunode.com/api/ebunode-userend/app-builds/webhook?token=<CODEMAGIC_WEBHOOK_SECRET>`.
   (Ebunode also checks running builds every minute, so a missed webhook only delays the update.)

Put the values in the Ebunode API's `.env`:

```
CODEMAGIC_API_TOKEN=
CODEMAGIC_APP_ID=
CODEMAGIC_WEBHOOK_SECRET=
```

## Running it locally

```
flutter pub get
flutter run --dart-define=APP_URL=https://glow-salon.ebunode.app --dart-define=APP_NAME="Glow Salon"
```
