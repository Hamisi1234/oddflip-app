# Red Card Alert mobile release

The native package identity is `com.redcardalert.app`. Do not publish under this
identity until ownership and naming have been confirmed; store package IDs
cannot be changed after release.

## Prerequisites

- Node.js and pnpm versions from `.mise.toml`
- Android Studio with a current Android SDK and JDK
- macOS with Xcode for iOS builds
- Google Play Console account
- Apple Developer Program account
- A deployed HTTPS backend

## Production frontend configuration

The native WebView cannot use the local Vite middleware. Build with the hosted
backend URL:

```sh
VITE_API_BASE_URL=https://api.example.com pnpm mobile:sync
```

The backend must allow the native application origin and must never expose
`SPORTRADAR_API_KEY` to the WebView.

## Firebase

These files contain project-specific identifiers and must be downloaded from
the Firebase Console:

- Android: `android/app/google-services.json`
- iOS: `ios/App/App/GoogleService-Info.plist`

Enable Cloud Messaging for both Firebase apps and use the package/bundle ID
`com.redcardalert.app`. Add APNs authentication credentials in Firebase for iOS.
Device-token upload and Firebase Admin dispatch still require production backend
endpoints and durable device storage.

## Android

```sh
pnpm mobile:sync
pnpm android:open
```

In Android Studio:

1. Confirm the production backend is configured.
2. Add the Firebase configuration.
3. Create a release signing key and keep it outside the repository.
4. Build a signed Android App Bundle (`.aab`).
5. Upload it to Play Console internal testing before production.

## iOS

```sh
pnpm mobile:sync
pnpm ios:open
```

On macOS in Xcode:

1. Select the correct Apple development team.
2. Enable Push Notifications and Background Modes → Remote notifications.
3. Add the Firebase plist.
4. Set signing and distribution certificates.
5. Archive and upload through App Store Connect.

## Store requirements

- 1024×1024 app icon without transparency
- Android adaptive icon and feature graphic
- iPhone and Android screenshots
- Privacy Policy and support URLs
- Accurate data-safety and App Privacy declarations
- Account-deletion flow if user accounts are added
- Sports-data display/redistribution rights
- Reviewer test instructions
