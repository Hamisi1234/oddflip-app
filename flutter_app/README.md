# Red Card Alert Flutter

Flutter mobile client yenye:

- Live Matches Dashboard
- Upcoming matches with kickoff times
- Team and league search across live and upcoming matches
- Match Details Timeline
- Mkamaria AI chat with contextual live/upcoming match analysis and structured
  betslip cards
- Red/Yellow Card Alert dialog
- Alert Settings
- Live red-card notifications and an in-app alert sound, controlled separately
  from Settings

Red-card alerts are checked every 20 seconds while the app is running and live
match monitoring is available. Allow notifications when prompted; red-card
notifications and the alarm can each be enabled or disabled in Settings.

## Tengeneza native platform files (mara moja)

Flutter SDK haipo ndani ya repository. Baada ya kui-install:

```bash
cd flutter_app
flutter create . --platforms=android,ios --org com.redcardalert
flutter pub get
```

`flutter create` huhifadhi files za `lib/` zilizopo na hutengeneza Android/iOS
runner files. Hakikisha Android application ID ni `com.redcardalert.app` kwenye
`android/app/build.gradle.kts`; ikiwa command imetengeneza
`com.redcardalert.red_card_alert`, ibadilishe kwenye `namespace` na
`applicationId`.

## Run

Android Emulator hutumia special host `10.0.2.2`, ambayo tayari ndiyo default:

```bash
flutter run
```

Kwa simu halisi, tumia IPv4 ya computer kwenye Wi-Fi moja:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

Kwa production lazima API iwe HTTPS:

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com
```

Mkamaria AI is available from the bottom navigation after login. It calls
`POST /api/mkaria-chat`; the Laravel API must have a valid `GROQ_API_KEY`, and
the account must have an active trial or paid subscription. The chat can use
cached live/upcoming fixtures and the currently selected match. No odds provider
is connected, so betslip odds are shown as unavailable rather than estimated.
